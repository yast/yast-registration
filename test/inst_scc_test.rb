#! /usr/bin/env rspec

require_relative "spec_helper"
require "yast"

require "registration/clients/inst_scc"

describe Yast::InstSccClient do
  before do
    # generic UI stubs for the wizard dialog
    Yast.import "UI"
    allow(Yast::UI).to receive(:WizardCommand)
    allow(Yast::UI).to receive(:WidgetExists).and_return(true)
    allow(Yast::UI).to receive(:ChangeWidget)
    allow(Yast::UI).to receive(:SetFocus)
    allow(Yast::UI).to receive(:ReplaceWidget)
    allow(Yast::Mode).to receive(:update).and_return(false)
    allow(Yast::SlpService).to receive(:all).and_return([])
    allow(Y2Packager::MediumType).to receive(:online?).and_return(false)
    allow(Registration::Addon).to receive(:find_all).and_return([])
  end

  context "the system is already registered" do
    before do
      expect(Registration::Registration).to receive(:is_registered?).at_least(:once)
        .and_return(true)
      expect(Registration::SwMgmt).to receive(:find_base_product).at_least(:once)
        .and_return("name" => "SLES")
    end

    it "returns :abort when closing the status dialog" do
      # user closes the dialog via window manager
      expect(Yast::UI).to receive(:UserInput).and_return(:cancel)
      expect(subject.main).to eq(:abort)
    end

    it "displays an error when loading the available extensions fails" do
      error = "Invalid system credentials"
      # click installing extensions, abort the workflow
      expect(Yast::UI).to receive(:UserInput).and_return(:extensions, :abort)

      expect(Yast::Report).to receive(:Error) do |msg|
        # make sure the propoer error is displayed
        expect(msg).to include(error)
      end

      expect_any_instance_of(Registration::RegistrationUI).to receive(:get_available_addons)
        .and_raise(error)

      expect(subject.main).to eq(:abort)
    end
  end

  context "the system is updating reusing old credentials" do
    before do
      expect(subject).to receive(:registration_check)
        .and_return(:update)
    end

    it "switchs to manual registration when aborting selection of url" do
      # User cancels the selection of registration url
      expect_any_instance_of(Registration::UI::RegistrationUpdateDialog).to receive(
        :init_registration
      ).and_return(:cancel)
      # So manual registration dialog is displayed
      expect(subject).to receive(:register_base_system)
        .and_return(:cancel)
      expect(subject.main).to eq(:abort)
    end
  end
end
