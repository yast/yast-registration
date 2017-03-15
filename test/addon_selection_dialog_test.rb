require_relative "spec_helper"
require "registration/addon"

describe Registration::UI::AddonSelectionRegistrationDialog do
  before(:each) do
    # generic UI stubs for the wizard dialog
    allow(Yast::UI).to receive(:WizardCommand)
    allow(Yast::UI).to receive(:WidgetExists).and_return(true)
    allow(Yast::UI).to receive(:ChangeWidget)
    allow(Yast::UI).to receive(:SetFocus)
    allow(Yast::UI).to receive(:ReplaceWidget)
    allow(Yast::UI).to receive(:TextMode).and_return(false)

    # empty hash for any base product, it does not matter
    allow(Registration::SwMgmt).to receive(:base_product_to_register).and_return({})

    addon_reset_cache
  end

  describe "#initialize" do
    it "sets the beta filter to the previous state" do
      fake_ref = double.as_null_object
      registration = double(activated_products: [], get_addon_list: [])
      res = described_class.new(registration)
      res.send(:filter_beta_releases, false)

      expect_any_instance_of(described_class).to receive(:filter_beta_releases).with(false)
      described_class.new(fake_ref)
    end
  end

  describe ".run" do
    subject { Registration::UI::AddonSelectionRegistrationDialog }

    let(:toolchain) do
      Registration::Addon.new(
        addon_generator("zypper_name" => "sle-module-toolchain",
        "name" => "Toolchain module", "version" => "12", "arch" => "aarch64")
      )
    end

    it "returns response from addon selection according to pressed button" do
      expect(Yast::UI).to receive(:UserInput).and_return(:abort)
      registration = double(activated_products: [], get_addon_list: [])
      expect(subject.run(registration)).to eq :abort
    end

    it "returns `:skip` if no addon is selected and user click next" do
      expect(Yast::UI).to receive(:UserInput).and_return(:next)
      registration = double(activated_products: [], get_addon_list: [])
      expect(subject.run(registration)).to eq :skip
    end

    it "returns `:next` if some addons are selected and user click next" do
      addon = addon_generator
      widget = "#{addon.identifier}-#{addon.version}-#{addon.arch}"
      expect(Yast::UI).to receive(:UserInput).and_return(widget, :next)
      registration = double(activated_products: [], get_addon_list: [addon])
      expect(subject.run(registration)).to eq :next

      addons = Registration::Addon.find_all(registration)
      wrapped_addon = addons.first
      expect(wrapped_addon.selected?).to eq true
    end

    context "in SLES12-SP2" do
      let(:registration) { double }

      before do
        # SLES12-SP2
        allow(Registration::SwMgmt).to receive(:base_product_to_register)
          .and_return("name" => "SLES", "version" => "12.2")
        allow(Registration::Addon).to receive(:find_all).and_return([toolchain])
        allow(Yast::UI).to receive(:UserInput).and_return(:next)
      end

      context "on the ARM64 architecture" do
        before do
          expect(Yast::Arch).to receive(:aarch64).and_return(true)
        end

        it "preselects the Toolchain module" do
          expect(toolchain).to receive(:selected)
          subject.run(registration)
        end
      end

      context "on the other architectures" do
        before do
          expect(Yast::Arch).to receive(:aarch64).and_return(false)
        end

        it "does not preselect the Toolchain module" do
          expect(toolchain).to_not receive(:selected)
          subject.run(registration)
        end
      end
    end

    context "in SLES12-SP3" do
      let(:registration) { double }

      before do
        # SLES12-SP3
        allow(Registration::SwMgmt).to receive(:base_product_to_register)
          .and_return("name" => "SLES", "version" => "12.3")
        allow(Registration::Addon).to receive(:find_all).and_return([toolchain])
        allow(Yast::UI).to receive(:UserInput).and_return(:next)
      end

      context "on the ARM64 architecture" do
        before do
          expect(Yast::Arch).to receive(:aarch64).and_return(true)
        end

        it "does not preselect the Toolchain module" do
          expect(toolchain).to_not receive(:selected)
          subject.run(registration)
        end
      end
    end
  end

  describe "#handle_dialog" do
    subject do
      registration = double(activated_products: [], get_addon_list: [])
      Registration::UI::AddonSelectionRegistrationDialog.new(registration)
    end

    it "filters beta releases" do
      expect(Yast::UI).to receive(:UserInput).and_return(:filter_beta, :next)

      expect(Yast::UI).to receive(:QueryWidget)
        .with(Yast::Term.new(:id, :filter_beta), :Value)
        .and_return(true)
      expect(subject).to receive(:filter_beta_releases).with(true)

      expect(subject.send(:handle_dialog)).to_not eq :back
    end
  end
end
