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
      expect(Registration::Registration).to receive(:is_registered?).at_least(:once).and_return(true)
      expect(Registration::SwMgmt).to receive(:find_base_product).at_least(:once).and_return("name" => "SLES")
    end

    it "returns :abort when closing the status dialog" do
      # user closes the dialog via window manager
      expect(Yast::UI).to receive(:UserInput).and_return(:cancel)
      expect(Yast::WFM.call("inst_scc")).to eq(:abort)
    end

    it "goes back to initial screen when aborting selection of url" do
      # User clicks on 'select extensions' first time the initial screen is
      # displayed and 'finish' the second time
      expect(Yast::UI).to receive(:UserInput).and_return(:extensions, :next)
      # User cancels the selection of registration url
      expect_any_instance_of(Yast::InstSccClient).to receive(:init_registration).and_return(:cancel)
      # Initial screen is displayed twice
      expect_any_instance_of(Yast::InstSccClient).to receive(:registration_check).twice.and_call_original

      expect(Yast::WFM.call("inst_scc")).to eq(:next)
    end
  end

  context "the system is updating reusing old credentials" do
    before do
      expect_any_instance_of(Yast::InstSccClient).to receive(:registration_check).and_return(:update)
    end

    it "switchs to manual registration when aborting selection of url" do
      # User cancels the selection of registration url
      expect_any_instance_of(Yast::InstSccClient).to receive(:init_registration).and_return(:cancel)
      # So manual registration dialog is displayed
      expect_any_instance_of(Yast::InstSccClient).to receive(:register_base_system).and_return(:cancel)
      expect(Yast::WFM.call("inst_scc")).to eq(:abort)
    end
  end

end
