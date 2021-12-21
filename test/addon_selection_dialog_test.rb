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
    it "sets the development filter to the previous state" do
      fake_ref = double.as_null_object
      registration = double(activated_products: [], get_addon_list: [])
      res = described_class.new(registration)
      res.send(:filter_devel_releases, false)

      expect_any_instance_of(described_class).to receive(:filter_devel_releases).with(false)
      described_class.new(fake_ref)
    end
  end

  describe ".run" do
    subject { Registration::UI::AddonSelectionRegistrationDialog }

    let(:registration) { double(activated_products: [], get_addon_list: []) }
    let(:filter_devel) { false }
    let(:recommended_addon) { addon_generator("recommended" => true) }

    before do
      allow(described_class).to receive(:filter_devel).and_return(filter_devel)
      allow(Yast::UI).to receive(:TextMode).and_return(false)
      allow(Yast::UI).to receive(:UserInput).and_return(:next)
      allow_any_instance_of(described_class).to receive(:RichText).and_call_original
    end

    it "returns response from addon selection according to pressed button" do
      expect(Yast::UI).to receive(:UserInput).and_return(:abort)
      expect(subject.run(registration)).to eq :abort
    end

    it "returns `:skip` if no addon is selected and user click next" do
      expect(Yast::UI).to receive(:UserInput).and_return(:next)
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

    context "a recommended addon is available" do
      let(:registration) { double(activated_products: [], get_addon_list: [recommended_addon]) }

      before do
        allow(Registration::Addon).to receive(:selected).and_return([])
        allow(Registration::Addon).to receive(:registered).and_return([])
      end

      it "preselects the recommended addons" do
        # check the displayed content
        expect_any_instance_of(described_class).to receive(:RichText)
          .with(Yast::Term.new(:id, :items), /checkbox-on\.png/).and_call_original
        expect_any_instance_of(described_class).to_not receive(:RichText)
          .with(Yast::Term.new(:id, :items), /checkbox-off\.png/)

        subject.run(registration)
      end

      it "does not preselect the recommended addons if something is already selected" do
        # just to have an unknown, but "selected" addon for the Addon.selected call
        expect(Registration::Addon).to receive(:selected).and_return([addon_generator])
          .at_least(:once)

        # check the displayed content
        expect_any_instance_of(described_class).to receive(:RichText)
          .with(Yast::Term.new(:id, :items), /checkbox-off\.png/).and_call_original
        expect_any_instance_of(described_class).to_not receive(:RichText)
          .with(Yast::Term.new(:id, :items), /checkbox-on\.png/)

        subject.run(registration)
      end

      it "does not preselect the recommended addons if something is already registered" do
        # just to have an unknown, but "registered" addon for the Addon.registered call
        expect(Registration::Addon).to receive(:registered).and_return([addon_generator])
          .at_least(:once)

        # check the displayed content
        expect_any_instance_of(described_class).to receive(:RichText)
          .with(Yast::Term.new(:id, :items), /checkbox-off\.png/).and_call_original
        expect_any_instance_of(described_class).to_not receive(:RichText)
          .with(Yast::Term.new(:id, :items), /checkbox-on\.png/)

        subject.run(registration)
      end
    end

    it "works in textmode" do
      pending "YaML loading of older OpenStruct is broken in ruby3" if RUBY_VERSION =~ /3\.0\.\d+/
      allow(Yast::UI).to receive(:TextMode).and_return(true)
      addons = load_yaml_fixture("sle15_addons.yaml")
      allow(Registration::Addon).to receive(:find_all).and_return(addons)

      addons.find { |a| a.identifier == "sle-we" }.selected

      registration = double(activated_products: [], get_addon_list: [addons])

      expect(Yast::UI).to receive(:UserInput).and_return(:next)
      expect(subject.run(registration)).to eq :next
    end

    it "recomputes auto_selection after each widget change" do
      pending "YaML loading of older OpenStruct is broken in ruby3" if RUBY_VERSION =~ /3\.0\.\d+/
      addons = load_yaml_fixture("sle15_addons.yaml")
      allow(Registration::Addon).to receive(:find_all).and_return(addons)

      addon = addons.find { |a| a.identifier == "sle-we" }

      widget = "#{addon.identifier}-#{addon.version}-#{addon.arch}"

      expect(Yast::UI).to receive(:UserInput).and_return(widget, :next)
      expect(subject.run(registration)).to eq :next

      expect(addon.selected?).to eq true

      child = addons.find { |a| a.identifier == "sle-module-desktop-applications" }
      expect(child.auto_selected?).to eq true
    end

    context "when development versions are not filtered" do
      let(:addon) do
        Registration::Addon.new(
          addon_generator
        )
      end
      subject(:dialog) { described_class.new(registration) }
      let(:filter_devel) { false }

      it "sets the filter as not checked in the UI" do
        allow(addon).to receive(:released?).and_return(false)
        allow(addon).to receive(:registered?).and_return(false)
        allow(Registration::Addon).to receive(:find_all).and_return([addon])
        expect(dialog).to receive(:CheckBox)
          .with(Yast::Term.new(:id, :filter_devel), anything, anything, filter_devel)
          .and_call_original
        dialog.run
      end

      it "displays development add-ons" do
        allow(addon).to receive(:released?).and_return(false)
        allow(Registration::Addon).to receive(:find_all).and_return([addon])
        expect(subject).to receive(:RichText).with(Yast::Term.new(:id, :items), /#{addon.name}/)
        allow(subject).to receive(:RichText).and_call_original
        dialog.run
      end
    end

    context "when development versions are filtered" do
      let(:addon) do
        Registration::Addon.new(
          addon_generator
        )
      end
      subject(:dialog) { described_class.new(registration) }
      let(:filter_devel) { true }

      it "sets the filter as checked in the UI" do
        allow(addon).to receive(:released?).and_return(false)
        allow(addon).to receive(:registered?).and_return(false)
        allow(Registration::Addon).to receive(:find_all).and_return([addon])
        expect(dialog).to receive(:CheckBox)
          .with(Yast::Term.new(:id, :filter_devel), anything, anything, filter_devel)
          .and_call_original
        dialog.run
      end

      it "does not display development add-ons that are not registered" do
        allow(addon).to receive(:released?).and_return(false)
        allow(addon).to receive(:registered?).and_return(false)
        allow(Registration::Addon).to receive(:find_all).and_return([addon])
        expect(subject).to receive(:RichText).with(Yast::Term.new(:id, :items), "")
        allow(subject).to receive(:RichText).and_call_original
        dialog.run
      end

      it "display registered development add-ons" do
        allow(addon).to receive(:released?).and_return(false)
        allow(addon).to receive(:registered?).and_return(true)
        allow(Registration::Addon).to receive(:find_all).and_return([addon])
        expect(subject).to receive(:RichText).with(Yast::Term.new(:id, :items), /#{addon.name}/)
        allow(subject).to receive(:RichText).and_call_original
        dialog.run
      end

      it "displays recommended development add-ons" do
        allow(addon).to receive(:released?).and_return(false)
        allow(addon).to receive(:registered?).and_return(false)
        allow(addon).to receive(:recommended).and_return(true)
        allow(Registration::Addon).to receive(:find_all).and_return([addon])
        expect(subject).to receive(:RichText).with(Yast::Term.new(:id, :items), /#{addon.name}/)
        allow(subject).to receive(:RichText).and_call_original
        dialog.run
      end

      it "displays auto-selected development add-ons" do
        allow(addon).to receive(:released?).and_return(false)
        allow(addon).to receive(:registered?).and_return(false)
        allow(addon).to receive(:recommended).and_return(false)
        allow(addon).to receive(:auto_selected?).and_return(true)
        allow(Registration::Addon).to receive(:find_all).and_return([addon])
        expect(subject).to receive(:RichText).with(Yast::Term.new(:id, :items), /#{addon.name}/)
        allow(subject).to receive(:RichText).and_call_original
        dialog.run
      end
    end

    context "when there is no development versions to filter" do
      subject(:dialog) { described_class.new(registration) }

      it "shows no filter in the UI" do
        expect(dialog).to_not receive(:CheckBox)
        dialog.run
      end
    end
  end

  describe "#handle_dialog" do
    subject do
      registration = double(activated_products: [], get_addon_list: [])
      Registration::UI::AddonSelectionRegistrationDialog.new(registration)
    end

    it "filters development releases" do
      expect(Yast::UI).to receive(:UserInput).and_return(:filter_devel, :next)

      expect(Yast::UI).to receive(:QueryWidget)
        .with(Yast::Term.new(:id, :filter_devel), :Value)
        .and_return(true)
      expect(subject).to receive(:filter_devel_releases).with(true)

      expect(subject.send(:handle_dialog)).to_not eq :back
    end
  end
end
