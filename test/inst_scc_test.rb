#! /usr/bin/env rspec

require_relative "spec_helper"

require "yast"
require "registration/registration"

describe "inst_scc client" do

  before do
    # generic UI stubs for the wizard dialog
    Yast.import "UI"
    allow(Yast::UI).to receive(:WizardCommand)
    allow(Yast::UI).to receive(:WidgetExists).and_return(true)
    allow(Yast::UI).to receive(:ChangeWidget)
    allow(Yast::UI).to receive(:SetFocus)
    allow(Yast::UI).to receive(:ReplaceWidget)
  end

  context "the system is already registered" do
    before do
      expect(Registration::Registration).to receive(:is_registered?).and_return(true)
    end

    it "returns :abort when closing the status dialog" do
      # user closes the dialog via window manager
      expect(Yast::UI).to receive(:UserInput).and_return(:cancel)
      expect(Yast::WFM.call("inst_scc")).to eq(:abort)
    end
  end

end
