#! /usr/bin/env rspec

require_relative "spec_helper"
require_relative "yast_stubs"

describe "Registration::Registration" do
  let(:yast_wfm) { double("Yast::Wfm") }

  before do
    stub_yast_require
    require "registration/registration"

    stub_const("Yast::WFM", yast_wfm)
    allow(yast_wfm).to receive(:GetLanguage).and_return("en")
    allow(Registration::Helpers).to receive(:insecure_registration).and_return(false)
  end

  describe ".register" do
    it "registers the system using the provided registration code" do
      username = "user"
      password = "password"
      reg_code = "reg_code"
      target_distro = "sles-12-x86_64"

      expect(Registration::SwMgmt).to receive(:zypp_config_writable!)
      expect_any_instance_of(SUSE::Connect::Credentials).to receive(:write)
      expect(SUSE::Connect::YaST).to(receive(:announce_system)
        .with(hash_including(:token => reg_code), target_distro)
        .and_return([username, password])
      )

      Registration::Registration.new.register("email", reg_code, target_distro)
    end
  end

  # product registration and product upgrade behave the same, they only
  # call a different connect funtion internally
  shared_examples "add_product" do |connect_method, yast_method|
    it "adds the selected product and returns added zypp services" do
      product = {
        "arch" => "x86_64",
        "name" => "SLES",
        "version" => "12",
        "release_type" => "DVD"
      }

      service_data = {
        "name" => "service",
        "url" => "https://example.com",
        "product" => product
      }

      service = SUSE::Connect::Remote::Service.new(service_data)

      expect(SUSE::Connect::YaST).to receive(connect_method).and_return(service)

      expect(Registration::SwMgmt).to receive(:add_service)
      allow(File).to receive(:exist?).with(
        SUSE::Connect::Credentials::GLOBAL_CREDENTIALS_FILE).and_return(true)
      allow(File).to receive(:read).with(
        SUSE::Connect::Credentials::GLOBAL_CREDENTIALS_FILE).and_return(
        "username=SCC_foo\npassword=bar")

      registered_service = Registration::Registration.new.send(yast_method, product)
      expect(registered_service).to eq(service)
    end
  end

  describe ".register_product" do
    it_should_behave_like "add_product", :activate_product, :register_product
  end

  describe ".upgrade_product" do
    it_should_behave_like "add_product", :upgrade_product, :upgrade_product
  end

  describe ".activated_products" do
    it "returns list of activated products" do
      expect(SUSE::Connect::Status).to receive(:activated_products).and_return([])

      expect(Registration::Registration.new.activated_products).to be_an(Array)
    end
  end

  describe "#get_addon_list" do
    let(:base_product) do
      {
        "name" => "SLES",
        "version" => "12",
        "arch" => "x86_64",
        "release_type" => "DVD"
      }
    end
    before do
      expect(Registration::SwMgmt).to receive(:base_product_to_register).and_return(base_product)
    end

    it "downloads available extensions" do
      remote_product = YAML.load_file(fixtures_file("remote_product.yml"))
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
    let(:context) { double(:error => error_code, :error_string => error_string) }

    it "stores the SSL error details" do
      certificate = File.read(fixtures_file("test.pem"))
      expect(context).to receive(:current_cert).and_return(certificate).twice

      storage = Registration::Storage::SSLErrors.instance
      expect(storage).to receive(:ssl_error_code=).with(error_code)
      expect(storage).to receive(:ssl_error_msg=).with(error_string)
      expect(storage).to receive(:ssl_failed_cert=)\
        .with(an_instance_of(Registration::SslCertificate))

      expect { callback.call(false, context) }.to_not raise_error
    end

    it "logs the exception raised inside" do
      # set an invalid certificate to throw an exception in the callback
      expect(context).to receive(:current_cert)\
        .and_return("INVALID CERTIFICATE").twice

      logger = double
      expect(logger).to receive(:error).with(/SSL verification failed:/)
      # the exception is logged
      expect(logger).to receive(:error).with(
        /Exception in SSL verify callback: OpenSSL::X509::CertificateError/)

      allow(registration).to receive(:log).and_return(logger)

      # the exception is re-raised
      expect { callback.call(false, context) }.to raise_error OpenSSL::X509::CertificateError
    end
  end

end
