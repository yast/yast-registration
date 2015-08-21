require_relative "spec_helper"

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
  end
end
