#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/registration"
require "registration/registration_ui"

describe "Registration::RegistrationUI" do
  let(:registration) { Registration::Registration.new }
  let(:registration_ui) { Registration::RegistrationUI.new(registration) }

  describe "#register_system_and_base_product" do
    it "registers the system using the provided registration code" do
      email = "user@example.com"
      reg_code = "reg_code"
      
      target_distro = "sles-12-x86_64"
      base_product = { "arch" => "x86_64", "name" => "SLES", "version" => "12",
        "flavor" => "DVD", "register_target" => target_distro }
      base_product_to_register = { "name"=>"SLES", "arch"=>"x86_64",
        "version"=>"12", "release_type"=>"DVD", "reg_code"=>"reg_code" }

      expect(Registration::Registration).to receive(:is_registered?).and_return(false)
      expect(Registration::SwMgmt).to receive(:find_base_product).twice.and_return(base_product)
      expect(registration).to receive(:register).with(email, reg_code, target_distro)
      expect(registration).to receive(:register_product).with(base_product_to_register, email).and_return([])

      expect(registration_ui.register_system_and_base_product(email, reg_code)).to be_true
    end
  end

  describe "#get_available_addons" do
    it "returns available addons" do
      expect(Registration::Addon).to receive(:find_all).with(registration).and_return([])
      
      expect(registration_ui.get_available_addons).to eql([])
    end
  end

end
