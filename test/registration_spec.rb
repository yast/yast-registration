#! /usr/bin/env rspec

require_relative "spec_helper"
require_relative "yast_stubs"

describe "Registration::Registration" do
  let(:yast_wfm) { double("Yast::Wfm") }

  before do
    stub_yast_require
    require "registration/registration"

    stub_const("Yast::WFM", yast_wfm)
    yast_wfm.stub(:GetLanguage).and_return("en")
    allow(Registration::Helpers).to receive(:insecure_registration).and_return(false)
  end

  describe ".register" do
    it "registers the system using the provided registration code" do
      username = "user"
      password = "password"
      reg_code = "reg_code"
      target_distro = "sles-12-x86_64"

      expect(Registration::SwMgmt).to receive(:zypp_config_writable!)
      SUSE::Connect::Credentials.any_instance.should_receive(:write)
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

end
