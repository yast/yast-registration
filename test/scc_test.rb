#! /usr/bin/env rspec

require_relative "spec_helper"

require "yast"
require "registration/sw_mgmt"
require "registration/registration"

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
    expect(Yast::Wizard).to receive(:CreateDialog)
    expect(Yast::Wizard).to receive(:CloseDialog)

    expect(Registration::SwMgmt).to receive(:init).and_return(true)
  end

  context "the system is already registered" do
    before do
      expect(Registration::Registration).to receive(:is_registered?).and_return(true)
    end

    it "returns :abort when closing the status dialog" do
      # user closes the dialog via window manager
      expect(Yast::UI).to receive(:UserInput).and_return(:cancel)
      expect(Yast::WFM.call("scc")).to eq(:abort)
    end
  end

end
