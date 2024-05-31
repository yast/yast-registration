#! /usr/bin/env rspec

require_relative "spec_helper"
require "yast"

describe "scc client" do
  before do
    # generic UI stubs for the wizard dialog
    Yast.import "UI"
    allow(Yast::UI).to receive(:WizardCommand)
    allow(Yast::UI).to receive(:WidgetExists).and_return(true)
    allow(Yast::UI).to receive(:ChangeWidget)
    allow(Yast::UI).to receive(:SetFocus)
    allow(Yast::UI).to receive(:ReplaceWidget)
    Yast.import "Wizard"
    allow(Yast::Wizard).to receive(:CreateDialog)
    allow(Yast::Wizard).to receive(:CloseDialog)

    allow(Registration::SwMgmt).to receive(:init)
    allow(Registration::SwMgmt).to receive(:find_base_product).and_return("name" => "SLES")
    allow(Registration::Registration).to receive(:is_registered?)
    allow(Registration::UrlHelpers).to receive(:slp_discovery_feedback).and_return([])
  end

  context "the system is already registered" do
    before do
      expect(Registration::Registration).to receive(:is_registered?).and_return(true)
      expect(Registration::Addon).to receive(:find_all).and_return([])
    end

    it "returns :abort when closing the status dialog" do
      # user closes the dialog via window manager
      expect(Yast::UI).to receive(:UserInput).and_return(:cancel)
      expect(Yast::WFM.call("scc")).to eq(:abort)
    end
  end
end
