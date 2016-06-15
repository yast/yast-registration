require_relative "spec_helper"
require "registration/addon"

describe Registration::UI::AddonSelectionRegistrationDialog do
  subject { Registration::UI::AddonSelectionRegistrationDialog }

  before(:each) do
    # generic UI stubs for the wizard dialog
    allow(Yast::UI).to receive(:WizardCommand)
    allow(Yast::UI).to receive(:WidgetExists).and_return(true)
    allow(Yast::UI).to receive(:ChangeWidget)
    allow(Yast::UI).to receive(:SetFocus)
    allow(Yast::UI).to receive(:ReplaceWidget)
    allow(Yast::UI).to receive(:TextMode).and_return(false)

    addon_reset_cache
  end

  describe ".run" do
    let(:toolchain) do
      Registration::Addon.new(
        addon_generator("zypper_name" => "sle-module-toolchain",
        "name" => "Toolchain module", "version" => "12", "arch" => "aarch64")
      )
    end

    before do
      # empty hash for any base product, it does not matter
      allow(Registration::SwMgmt).to receive(:base_product_to_register).and_return({})
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
      # mock that widget is selected
      expect(Yast::UI).to receive(:QueryWidget)
        .with(Yast::Term.new(:id, widget), :Value)
        .and_return(true)
      registration = double(activated_products: [], get_addon_list: [addon])
      expect(subject.run(registration)).to eq :next
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
end
