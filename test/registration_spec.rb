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

      expect(SUSE::Connect::YaST).to receive(:create_credentials_file)
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
        "product" => OpenStruct.new(product)
      }
    end

    let(:service) { OpenStruct.new(service_data) }
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

      allow(SUSE::Connect::YaST).to receive(:credentials)
        .with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        .and_return(OpenStruct.new(username: "SCC_foo", password: "bar"))
    end

    it "adds the selected product and returns added zypp services" do
      registered_service = subject.send(yast_method, product)
      expect(registered_service).to eq(service)
    end

    it "does not add the target system prefix if not at upgrade" do
      allow(Yast::Mode).to receive(:update).and_return(false)
      allow(Yast::Stage).to receive(:initial).and_return(false)
      expect(Yast::Installation).to_not receive(:destdir)

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
    before do
      remote_product = load_yaml_fixture("remote_product.yml")
      allow(SUSE::Connect::YaST).to receive(:show_product).and_return(remote_product)
      # no product renames defined
      allow(Registration::SwMgmt).to receive(:update_product_renames).with({})
      allow(Registration::SwMgmt).to receive(:base_product_to_register).and_return(base_product)
    end

    context "no base product found" do
      let(:base_product) { nil }

      it "returns empty list if no base product is found" do
        expect(Registration::Registration.new.get_addon_list).to eq([])
      end
    end

    context "a base product is found" do
      let(:base_product) do
        {
          "name"         => "SLES",
          "version"      => "12",
          "arch"         => "x86_64",
          "release_type" => "DVD"
        }
      end

      it "downloads available extensions" do
        pending "YaML loading of older OpenStruct is broken in ruby3" if RUBY_VERSION =~ /3\.0\.\d+/

        addons = Registration::Registration.new.get_addon_list

        # HA-GEO is extension for HA so it's not included in the list
        # also the base product must not be included in the list
        expect(addons.map(&:identifier)).to include("sle-we", "sle-sdk",
          "sle-module-legacy", "sle-module-web-scripting", "sle-module-public-cloud",
          "sle-module-adv-systems-management", "sle-hae")
      end

      it "uses version without release for connecting SCC" do
        expect(Registration::SwMgmt).to receive(:remote_product).with(
          base_product, version_release: false
        )
        Registration::Registration.new.get_addon_list
      end
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

    before do
      allow_any_instance_of(Registration::Registration).to receive(:connect_params)
        .and_return({})
    end

    it "returns migration products from the server" do
      expect(SUSE::Connect::YaST).to receive(:system_migrations)
        .with(installed_products, {})
        .and_return(migration_products)
      result = Registration::Registration.new.migration_products(installed_products)
      expect(result).to eq(migration_products)
    end
  end

  describe "#get_updates_list" do
    let(:self_update_id) { "SLES" }
    let(:self_update_version) { "15.4" }
    let(:base_product) { { "name" => "base" } }
    let(:installer_update_base_product) { { "name" => self_update_id } }
    let(:remote_product) { { "name" => "base" } }
    let(:updates) { ["http://updates.suse.com/sles12/"] }
    let(:suse_connect) { double("suse_connect") }

    before do
      allow(Registration::SwMgmt).to receive(:base_product_to_register).and_return(base_product)
      stub_const("SUSE::Connect::YaST", suse_connect)
    end

    it "returns an empty list if no base product is available or selected" do
      allow(Registration::SwMgmt).to receive(:base_product_to_register).and_return(nil)
      allow(Registration::SwMgmt).to receive(:installer_update_base_product).and_return(nil)
      expect(subject.get_updates_list).to eq([])
    end

    context "when the control file defines a self_update_id" do
      it "returns updates list from the server for the self update id and version" do
        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("globals", "self_update_id").and_return(self_update_id)
        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("globals", "self_update_version").and_return(self_update_version)
        expect(suse_connect).to receive(:list_installer_updates) do |product, _options|
          expect(product.identifier).to eq("SLES")
          expect(product.version).to eq("15.4")
          updates
        end
        expect(subject.get_updates_list).to eq(updates)
      end
    end

    context "when an exception connecting to the server takes place" do
      before do
        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("globals", "self_update_id").and_return(self_update_id)
        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("globals", "self_update_version").and_return(self_update_version)
        allow(suse_connect).to receive(:list_installer_updates).and_raise(Timeout::Error)
      end

      it "does not catch the error" do
        expect { subject.get_updates_list }.to raise_error(Timeout::Error)
      end
    end
  end

  describe "#synchronize_products" do
    before do
      allow_any_instance_of(Registration::Registration).to receive(:connect_params)
        .and_return({})
    end

    it "synchronizes the local products with the server" do
      expect(SUSE::Connect::YaST).to receive(:synchronize)
        .with([
                OpenStruct.new(
                  arch:         "x86_64",
                  identifier:   "SLES",
                  version:      "12",
                  release_type: nil
                )
              ], {})

      subject.synchronize_products([installed_sles])
    end
  end

  describe "#downgrade_product" do
    before do
      allow_any_instance_of(Registration::Registration).to receive(:connect_params)
        .and_return({})
    end

    it "downgrades the product registration" do
      expect(SUSE::Connect::YaST).to receive(:downgrade_product)
        .with(
          OpenStruct.new(
            arch:         "x86_64",
            identifier:   "SLES",
            version:      "12",
            release_type: nil
          ),
          {}
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

  describe ".allowed?" do
    let(:mode) { "normal" }
    let(:stage) { "initial" }
    let(:registered) { false }

    before do
      allow(Yast::Mode).to receive(:mode).and_return(mode)
      allow(Yast::Stage).to receive(:stage).and_return(stage)
      allow(Registration::Registration).to receive(:is_registered?).and_return(registered)
    end

    context "when system is not registered yet" do
      it "returns true" do
        expect(described_class.allowed?).to eq(true)
      end
    end

    context "when system is already registered" do
      let(:registered) { true }

      context "and running in normal mode" do
        it "returns true" do
          expect(described_class.allowed?).to eq(true)
        end
      end

      context "and running in firstboot stage" do
        let(:mode) { "installation" }
        let(:stage) { "firstboot" }

        it "returns true" do
          expect(described_class.allowed?).to eq(true)
        end
      end

      context "but running neither in normal mode nor in firstboot stage" do
        let(:mode) { "installation" }
        let(:stage) { "initial" }

        it "returns false" do
          expect(described_class.allowed?).to eq(false)
        end
      end
    end
  end
end
