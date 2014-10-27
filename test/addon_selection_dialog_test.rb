require_relative "spec_helper"
require "registration/ui/addon_selection_dialog"

describe Registration::UI::AddonSelectionDialog do
  subject { Registration::UI::AddonSelectionDialog }

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
    it "returns response from addon selection according to pressed button" do
      expect(Yast::UI).to receive(:UserInput).and_return(:abort)
      registration = double(:activated_products => [], :get_addon_list => [])
      expect(subject.run(registration)).to eq :abort
    end

    it "returns `:skip` if no addon is selected and user click next" do
      expect(Yast::UI).to receive(:UserInput).and_return(:next)
      registration = double(:activated_products => [], :get_addon_list => [])
      expect(subject.run(registration)).to eq :skip
    end

    it "returns `:next` if some addons are selected and user click next" do
      test_addon = addon_generator
      expect(Yast::UI).to receive(:UserInput).and_return(test_addon.identifier, :next)
      # mock that widget is selected
      expect(Yast::UI).to receive(:QueryWidget).
        with(Yast::Term.new(:id, test_addon.identifier), :Value).
        and_return(true)
      registration = double(:activated_products => [], :get_addon_list => [test_addon])
      expect(subject.run(registration)).to eq :next
    end
  end
end
