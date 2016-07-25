#! /usr/bin/env rspec

require_relative "spec_helper"
require "registration/ui/regservice_selection_dialog"

Yast.import "SlpService"

describe "discover_registration_services client" do
  context "when no SLP server is annnounced" do
    before do
      allow(Yast::SlpService).to receive(:all).and_return([])
    end

    it "returns nil and does not ask the user" do
      expect(Registration::UI::RegserviceSelectionDialog).to_not receive(:run)
      expect(Yast::WFM.call("discover_registration_services")).to be_nil
    end
  end

  context "when a SLP server is present" do
    let(:slp_url) { "https://example.com/register" }
    let(:slp_service) { double("service", slp_url: "service:registration.suse:smt:#{slp_url}") }

    before do
      allow(Yast::SlpService).to receive(:all).and_return([slp_service])
    end

    it "returns the SLP server selected by user" do
      expect(Registration::UI::RegserviceSelectionDialog).to receive(:run).and_return(slp_service)
      expect(Yast::WFM.call("discover_registration_services")).to eq(slp_url)
    end

    it "returns :cancel when the SLP dialog is canceled" do
      expect(Registration::UI::RegserviceSelectionDialog).to receive(:run).and_return(:cancel)
      expect(Yast::WFM.call("discover_registration_services")).to eq(:cancel)
    end
  end
end
