#! /usr/bin/env rspec

require_relative "spec_helper"

describe "Registration::RegistrationUI" do
  let(:registration) { Registration::Registration.new }
  let(:registration_ui) { Registration::RegistrationUI.new(registration) }
  let(:target_distro) { "sles-12-x86_64" }
  let(:base_product) do
    {
      "arch" => "x86_64", "name" => "SLES", "version" => "12",
      "flavor" => "DVD", "register_target" => target_distro
    }
  end
  let(:base_product_to_register) do
    {
      "arch"         => "x86_64",
      "name"         => "SLES",
      "reg_code"     => "reg_code",
      "release_type" => "DVD",
      "version"      => "12"
    }
  end

  let(:remote_addons) { load_yaml_fixture("available_addons.yml") }
  let(:addon_HA) { remote_addons[0] }
  let(:addon_HA_GEO) { remote_addons[1] }
  let(:addon_legacy) { remote_addons[4] }
  let(:addon_SDK) { remote_addons[7] }

  describe "#register_system_and_base_product" do
    it "registers the system using the provided registration code" do
      email = "user@example.com"
      reg_code = "reg_code"

      expect(Registration::Registration).to receive(:is_registered?).and_return(false)
      expect(Registration::SwMgmt).to receive(:find_base_product).twice.and_return(base_product)
      expect(registration).to receive(:register).with(email, reg_code, target_distro)
      expect(registration).to receive(:register_product).with(base_product_to_register, email)
        .and_return([])

      expect(registration_ui.register_system_and_base_product(email, reg_code)).to be_true
    end
  end

  describe "#get_available_addons" do
    it "returns available addons" do
      expect(Registration::Addon).to receive(:find_all).with(registration).and_return([])

      expect(registration_ui.get_available_addons).to eql([])
    end
  end

  describe "#update_system" do
    it "updates the system registration with the new target distro" do
      expect(Registration::SwMgmt).to receive(:find_base_product).and_return(base_product)
      expect(registration).to receive(:update_system).with(target_distro)

      expect(registration_ui.update_system).to be_true
    end
  end

  describe "#update_base_product" do
    it "updates the base product registration" do
      expect(Registration::SwMgmt).to receive(:find_base_product).and_return(base_product)
      expect(Registration::SwMgmt).to receive(:base_product_to_register)
        .and_return(base_product_to_register)
      remote_product = load_yaml_fixture("remote_product.yml")
      expect(registration).to receive(:upgrade_product).with(base_product_to_register)
        .and_return(remote_product)

      expect(registration_ui.update_base_product).to eql([true, remote_product])
    end
  end

  describe "#migration_products" do
    let(:installed_products) { load_yaml_fixture("installed_sles12_product.yml") }
    let(:migration_products) { load_yaml_fixture("migration_to_sles12_sp1.yml") }

    it "returns migration products from the server with UI feedback" do
      allow(Yast::UI).to receive(:OpenDialog)
      allow(Yast::UI).to receive(:CloseDialog)

      expect(registration).to receive(:migration_products)
        .with(installed_products)
        .and_return(migration_products)

      expect(registration_ui.migration_products(installed_products)).to eq(migration_products)
    end
  end
end
