#! /usr/bin/env rspec

require_relative "spec_helper"

describe "Registration::RegistrationUI" do
  subject(:registration_ui) { Registration::RegistrationUI.new(registration) }

  let(:registration) { Registration::Registration.new }
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
  let(:remote_addons) { YAML.load_file(fixtures_file("available_addons.yml")) }
  let(:addon_HA) { remote_addons[0] }
  let(:addon_HA_GEO) { remote_addons[1] }
  let(:addon_legacy) { remote_addons[4] }
  let(:addon_SDK) { remote_addons[7] }

  describe "#register_system_and_base_product" do
    it "registers the system using the provided registration code" do
      email = "user@example.com"
      reg_code = "reg_code"

      expect(Registration::Registration).to receive(:is_registered?).and_return(false)
      expect(Registration::SwMgmt).to receive(:find_base_product).exactly(3).times
        .and_return(base_product)
      expect(registration).to receive(:register).with(email, reg_code, target_distro)
      expect(registration).to receive(:register_product).with(base_product_to_register, email)
        .and_return([])

      options = Registration::Storage::InstallationOptions.instance
      allow(options).to receive(:email).twice.and_return(email)
      allow(options).to receive(:reg_code).and_return(reg_code)
      allow(options).to receive(:base_registered).and_return(false)

      expect(registration_ui.register_system_and_base_product).to eq([true, []])
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

      expect(registration_ui.update_system).to eq(true)
    end
  end

  describe "#update_base_product" do
    it "updates the base product registration" do
      expect(Registration::SwMgmt).to receive(:find_base_product).and_return(base_product)
      expect(Registration::SwMgmt).to receive(:base_product_to_register)
        .and_return(base_product_to_register)
      remote_product = YAML.load_file(fixtures_file("remote_product.yml"))
      expect(registration).to receive(:upgrade_product).with(base_product_to_register)
        .and_return(remote_product)

      expect(registration_ui.update_base_product).to eql([true, remote_product])
    end
  end

  describe "#register_addons" do
    before do
      # installation mode
      allow(Yast::Mode).to receive(:installation).and_return(true)
      allow(Yast::Mode).to receive(:normal).and_return(false)
      allow(Yast::Mode).to receive(:update).and_return(false)

      # Stub Popup.Feedback and other messages to user
      allow(Yast::UI).to receive(:OpenDialog)
      allow(Yast::UI).to receive(:CloseDialog)
      allow(Yast::Wizard).to receive(:SetContents)

      # stub the registration
      allow(registration).to receive(:register_product)
      allow(registration).to receive(:select_repositories)
    end

    it "does not ask for reg. code if all addons are free" do
      # user is not asked for any reg. code
      expect(Registration::UI::AddonRegCodesDialog).to_not receive(:run)

      # Register Legacy module
      registration_ui.register_addons([addon_legacy], {})
    end

    it "asks for a reg. code if there is some paid addon" do
      # User is asked for reg. codes
      expect(Registration::UI::AddonRegCodesDialog).to receive(:run)
        .with([addon_HA], {}).and_return(:next)

      # Register High Availability module
      registration_ui.register_addons([addon_HA], {})
    end

    it "registers all addons" do
      # Stub user interaction for reg codes
      allow(Registration::UI::AddonRegCodesDialog).to receive(:run).and_return(:next)

      # Register HA-GEO + SDK addons
      selected_addons = [addon_HA_GEO, addon_SDK]
      registration_ui.register_addons(selected_addons, {})

      # All selected addons are marked as registered
      expect(selected_addons.all?(&:registered?)).to eq(true)
    end

    it "returns :next if everything goes fine" do
      expect(registration_ui.register_addons([addon_legacy], {})).to eq :next
    end

    it "returns :back if some registration failed" do
      # FIXME: Since the code is not functional, there is currently no cleaner
      # way to mock a registration failure
      allow(registration_ui).to receive(:register_selected_addons).and_return false

      expect(registration_ui.register_addons([addon_legacy], {})).to eq :back
    end
  end
end
