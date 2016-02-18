#! /usr/bin/env rspec

require_relative "spec_helper"

describe "Registration::RegistrationUI" do
  subject(:registration_ui) { Registration::RegistrationUI.new(registration) }

  let(:registration) { Registration::Registration.new }
  let(:target_distro) { "sles-12-x86_64" }
  let(:base_product) do
    {
      "arch"            => "x86_64",
      "flavor"          => "DVD",
      "name"            => "SLES",
      "version"         => "12-0",
      "version_version" => "12",
      "register_target" => target_distro
    }
  end
  let(:base_product_to_register) do
    {
      "arch"         => "x86_64",
      "name"         => "SLES",
      "reg_code"     => "reg_code",
      "release_type" => nil,
      "version"      => "12"
    }
  end
  let(:remote_addons) { load_yaml_fixture("available_addons.yml") }
  let(:addon_HA) { remote_addons[3] }
  let(:addon_HA_GEO) { remote_addons[4] }
  let(:addon_legacy) { remote_addons[10] }
  let(:addon_SDK) { remote_addons[7] }
  let(:installed_sles) { load_yaml_fixture("products_legacy_installation.yml")[1] }

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
      remote_product = load_yaml_fixture("remote_product.yml")
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
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([])

      # stub the registration
      allow(registration).to receive(:register_product)
    end

    context "when the addons are free" do

      it "does not ask for reg. code if all addons are free" do
        # user is not asked for any reg. code
        expect(Registration::UI::AddonRegCodesDialog).to_not receive(:run)

        # Register Legacy module
        registration_ui.register_addons([addon_legacy], {})
      end

      it "returns :next if everything goes fine" do
        allow(registration_ui).to receive(:register_selected_addons) { true }
        expect(registration_ui.register_addons([addon_legacy], {})).to eq :next
      end

      it "returns :back if some registration failed" do
        # FIXME: Since the code is not functional, there is currently no cleaner
        # way to mock a registration failure
        allow(registration_ui).to receive(:register_selected_addons).and_return false

        expect(registration_ui.register_addons([addon_legacy], {})).to eq :back
      end

    end

    context "when the addons need reg. code" do

      it "returns :next if everything goes fine" do
        allow(Registration::UI::AddonRegCodesDialog).to receive(:run).and_return(:next)
        allow(registration_ui).to receive(:register_selected_addons).with(any_args) { true }

        selected_addons = [addon_HA_GEO, addon_SDK]
        expect(registration_ui.register_addons(selected_addons, {})).to eq :next
      end

      it "keep asking for a reg. code if some reg. code failed" do
        # Stub user interaction for reg codes
        allow(Registration::UI::AddonRegCodesDialog).to receive(:run).and_return(:next, :next)
        allow(registration_ui).to receive(:register_selected_addons)
          .with(any_args).and_return(false, true)

        # Register HA-GEO + SDK addons
        selected_addons = [addon_HA_GEO, addon_SDK]
        registration_ui.register_addons(selected_addons, {})
      end

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

  describe "#downgrade_product" do
    it "displays UI feedback and downgrades the product" do
      expect(Yast::UI).to receive(:OpenDialog)
      expect(Yast::UI).to receive(:CloseDialog)

      service = double("fake_service")
      expect(registration).to receive(:downgrade_product).with(installed_sles).and_return(service)
      expect(registration_ui.downgrade_product(installed_sles)).to eq([true, service])
    end
  end

  describe "#synchronize_products" do
    it "displays UI feedback and synchronizes the products" do
      expect(Yast::UI).to receive(:OpenDialog)
      expect(Yast::UI).to receive(:CloseDialog)

      products = [installed_sles]
      expect(registration).to receive(:synchronize_products).with(products)
      expect(registration_ui.synchronize_products(products)).to eq(true)
    end
  end
end
