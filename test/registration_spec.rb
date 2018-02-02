#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::Registration do
  let(:installed_sles) { load_yaml_fixture("products_legacy_installation.yml")[1] }
  before do
    allow(Yast::WFM).to receive(:GetLanguage).and_return("en")
    allow(Registration::Helpers).to receive(:insecure_registration).and_return(false)
  end

  describe "#register" do
    it "registers the system using the provided registration code" do
      username = "user"
      password = "password"
      reg_code = "reg_code"
      target_distro = "sles-12-x86_64"

      expect_any_instance_of(SUSE::Connect::Credentials).to receive(:write)
      expect(SUSE::Connect::YaST).to(receive(:announce_system)
        .with(hash_including(token: reg_code), target_distro)
        .and_return([username, password]))

      Registration::Registration.new.register("email", reg_code, target_distro)
    end
  end

  # product registration and product upgrade behave the same, they only
  # call a different connect funtion internally
  shared_examples "add_product" do |connect_method, yast_method|
    let(:available_addons) { load_yaml_fixture("available_addons.yml") }

    let(:product) do
      {
        "arch"              => "x86_64",
        "name"              => "sle-sdk",
        "version"           => "12",
        "release_type"      => nil,
        "identifier"        => "SLES_SAP",
        "former_identifier" => "SUSE_SLES_SAP"
      }
    end

    let(:service_data) do
      {
        "name"    => "service",
        "url"     => "https://example.com",
        "product" => product
      }
    end

    let(:service) { SUSE::Connect::Remote::Service.new(service_data) }
    let(:destdir) { "/foo" }

    before do
      expect(SUSE::Connect::YaST).to receive(connect_method).and_return(service)

      expect(Registration::SwMgmt).to receive(:add_service)

      expect(Registration::Addon).to receive(:find_all).and_return(available_addons)
      expect(available_addons.find { |addon| addon.identifier == "sle-sdk" }).to \
        receive(:registered)

      # the received product renames are passed to the software management
      expect(Registration::SwMgmt).to receive(:update_product_renames)
        .with("SUSE_SLES_SAP" => "SLES_SAP")

      allow(File).to receive(:exist?).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        .and_return(true)

      allow(File).to receive(:read).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        .and_return("username=SCC_foo\npassword=bar")
    end

    it "adds the selected product and returns added zypp services" do
      registered_service = subject.send(yast_method, product)
      expect(registered_service).to eq(service)
    end

    it "does not add the target system prefix if not at upgrade" do
      allow(Yast::Mode).to receive(:update).and_return(false)
      allow(Yast::Stage).to receive(:initial).and_return(false)
      expect(Yast::Installation).to_not receive(:destdir)

      expect(File).to receive(:exist?).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        .and_return(true)

      expect(File).to receive(:read).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        .and_return("username=SCC_foo\npassword=bar")

      subject.send(yast_method, product)
    end
  end

  describe "#register_product" do
    it_should_behave_like "add_product", :activate_product, :register_product
  end

  describe "#upgrade_product" do
    it_should_behave_like "add_product", :upgrade_product, :upgrade_product
  end

  describe "#update_system" do
    it "updates the system registration with the new target distro" do
      target_distro = "sles-12-x86_64"
      expect(SUSE::Connect::YaST).to receive(:update_system).with(anything, target_distro)
      Registration::Registration.new.update_system(target_distro)
    end
  end

  describe "#activated_products" do
    it "returns list of activated products" do
      status = double(activated_products: [])
      expect(SUSE::Connect::YaST).to receive(:status).and_return(status)

      expect(Registration::Registration.new.activated_products).to eq([])
    end
  end

  describe "#get_addon_list" do
    let(:base_product) do
      {
        "name"         => "SLES",
        "version"      => "12",
        "arch"         => "x86_64",
        "release_type" => "DVD"
      }
    end
    before do
      expect(Registration::SwMgmt).to receive(:base_product_to_register).and_return(base_product)
    end

    it "downloads available extensions" do
      remote_product = load_yaml_fixture("remote_product.yml")
      expect(SUSE::Connect::YaST).to receive(:show_product).and_return(remote_product)
      # no product renames defined
      expect(Registration::SwMgmt).to receive(:update_product_renames).with({})

      addons = Registration::Registration.new.get_addon_list

      # HA-GEO is extension for HA so it's not included in the list
      # also the base product must not be included in the list
      expect(addons.map(&:identifier)).to include("sle-we", "sle-sdk",
        "sle-module-legacy", "sle-module-web-scripting", "sle-module-public-cloud",
        "sle-module-adv-systems-management", "sle-hae")
    end
  end

  describe "#verify_callback" do
    let(:registration) { Registration::Registration.new }
    let(:callback) { registration.send(:verify_callback) }
    let(:error_code) { 19 }
    let(:error_string) { "self signed certificate in certificate chain" }
    # SSL error context
    let(:context) { double(error: error_code, error_string: error_string) }

    it "stores the SSL error details" do
      certificate = File.read(fixtures_file("test.pem"))
      expect(context).to receive(:current_cert).and_return(certificate).twice

      storage = Registration::Storage::SSLErrors.instance
      expect(storage).to receive(:ssl_error_code=).with(error_code)
      expect(storage).to receive(:ssl_error_msg=).with(error_string)
      expect(storage).to receive(:ssl_failed_cert=)
        .with(an_instance_of(Registration::SslCertificate))

      expect { callback.call(false, context) }.to_not raise_error
    end

    it "logs the exception raised inside" do
      # set an invalid certificate to throw an exception in the callback
      expect(context).to receive(:current_cert)
        .and_return("INVALID CERTIFICATE").twice

      logger = double
      expect(logger).to receive(:error).with(/SSL verification failed:/)
      # the exception is logged
      expect(logger).to receive(:error).with(
        /Exception in SSL verify callback: OpenSSL::X509::CertificateError/
      )

      allow(registration).to receive(:log).and_return(logger)

      # the exception is re-raised
      expect { callback.call(false, context) }.to raise_error OpenSSL::X509::CertificateError
    end
  end

  describe "#migration_products" do
    let(:installed_products) { load_yaml_fixture("installed_sles12_product.yml") }
    let(:migration_products) { load_yaml_fixture("migration_to_sles12_sp1.yml") }

    it "returns migration products from the server" do
      expect(SUSE::Connect::YaST).to receive(:system_migrations)
        .with(installed_products)
        .and_return(migration_products)
      result = Registration::Registration.new.migration_products(installed_products)
      expect(result).to eq(migration_products)
    end
  end

  describe "#get_updates_list" do
    let(:base_product) { { "name" => "base" } }
    let(:remote_product) { { "name" => "base" } }
    let(:updates) { ["http://updates.suse.com/sles12/"] }
    let(:suse_connect) { double("suse_connect") }

    before do
      allow(Registration::SwMgmt).to receive(:base_product_to_register).and_return(base_product)
      stub_const("SUSE::Connect::YaST", suse_connect)
    end

    it "returns updates list from the server for the self update id if defined" do
      expect(Registration::SwMgmt).to receive(:remote_product).with("name" => "self_update_id")
        .and_return("name" => "self_update_id")
      expect(Yast::ProductFeatures).to receive(:GetStringFeature)
        .with("globals", "self_update_id")
        .and_return("self_update_id")
      expect(suse_connect).to receive(:list_installer_updates)
        .with({ "name" => "self_update_id" }, anything)
        .and_return(updates)
      expect(subject.get_updates_list).to eq(updates)
    end

    it "returns updates list from the server for the base product" do
      expect(Registration::SwMgmt).to receive(:remote_product).with(base_product)
        .and_return(remote_product)
      expect(suse_connect).to receive(:list_installer_updates).with(remote_product, anything)
        .and_return(updates)
      expect(subject.get_updates_list).to eq(updates)
    end
  end

  describe "#synchronize_products" do
    it "synchronizes the local products with the server" do
      expect(SUSE::Connect::YaST).to receive(:synchronize)
        .with([
                OpenStruct.new(
                  arch:         "x86_64",
                  identifier:   "SLES",
                  version:      "12",
                  release_type: nil
                )
              ])

      subject.synchronize_products([installed_sles])
    end
  end

  describe "#downgrade_product" do
    it "downgrades the product registration" do
      expect(SUSE::Connect::YaST).to receive(:downgrade_product)
        .with(
          OpenStruct.new(
            arch:         "x86_64",
            identifier:   "SLES",
            version:      "12-0",
            release_type: nil
          ),
          anything
        )

      expect(subject.downgrade_product(installed_sles))
    end
  end

  describe ".is_registered?" do
    it "returns true if the global credentials file exists" do
      expect(File).to receive(:exist?).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        .and_return(true)
      expect(Registration::Registration.is_registered?).to eq(true)
    end

    it "returns false if the global credentials file does not exist" do
      expect(File).to receive(:exist?).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        .and_return(false)
      expect(Registration::Registration.is_registered?).to eq(false)
    end
  end
end
