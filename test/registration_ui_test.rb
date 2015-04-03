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
  let(:remote_addons) { YAML.load_file(fixtures_file("available_addons.yml")) }

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

      # Popup.Feedback
      allow(Yast::UI).to receive(:OpenDialog)
      allow(Yast::UI).to receive(:CloseDialog)

      # stub the registration call
      expect(registration).to receive(:register_product).twice.and_return([])

      # stub service processing
      expect(Registration::SwMgmt).to receive(:service_repos)
        .with([], only_updates: true).twice.and_return([])
      expect(Registration::SwMgmt).to receive(:set_repos_state)
        .with([], true).twice
      expect(registration_ui).to receive(:install_updates?).twice.and_return(true)
    end

    it "registeres free addons without asking for a reg. code" do
      # Legacy module + SDK
      selected_addons = [remote_addons[4], remote_addons[7]]

      expect(Yast::Wizard).to receive(:SetContents)

      # user is not asked for any reg. code
      expect(Registration::UI::AddonRegCodesDialog).to_not receive(:run)

      # UI returns :next and all selected addons are marked as registered
      expect(registration_ui.register_addons(selected_addons, {})).to eq(:next)
      expect(selected_addons.all?(&:registered?)).to eq(true)
    end

    it "registeres paid addons after asking for a reg. code" do
      # HA + HA-GEO addons
      selected_addons = [remote_addons[0], remote_addons[1]]

      # user is asked for reg. codes
      expect(Registration::UI::AddonRegCodesDialog).to receive(:run)
        .with(selected_addons, {}).and_return(:next)

      # UI returns :next and all selected addons are marked as registered
      expect(registration_ui.register_addons(selected_addons, {})).to eq(:next)
      expect(selected_addons.all?(&:registered?)).to eq(true)
    end
  end
end
