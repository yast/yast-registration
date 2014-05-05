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

      expect(Registration::SwMgmt).to receive(:zypp_config_writable!)
      SUSE::Connect::Credentials.any_instance.should_receive(:write)
      expect(SUSE::Connect::YaST).to(receive(:announce_system)
        .with(hash_including(:token => reg_code))
        .and_return([username, password])
      )

      Registration::Registration.new.register("email", reg_code, "sles-12-x86_64")
    end
  end

  describe ".register_product" do
    it "registers the selected product and returns added zypp services" do
      product = {
        "arch" => "x86_64",
        "name" => "SLES",
        "version" => "12",
        "release_type" => "DVD"
      }

      source = SUSE::Connect::Source.new("service", "https://example.com")
      service = SUSE::Connect::Service.new([source], [], [])

      expect(SUSE::Connect::YaST).to(receive(:activate_product)
        .with(hash_including(
            :product_ident => {
              :name => product["name"],
              :version => product["version"],
              :arch => product["arch"],
              :release_type => product["release_type"]
            }
          ))
        .and_return(service)
      )

      expect(Registration::SwMgmt).to receive(:add_services)
      expect(SUSE::Connect::Credentials).to receive(:read)
        .with(SUSE::Connect::Credentials::GLOBAL_CREDENTIALS_FILE)

      service_list = Registration::Registration.new.register_product(product)
      expect(service_list).to eq([service])
    end
  end

end
