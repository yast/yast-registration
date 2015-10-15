#! /usr/bin/env rspec

require_relative "spec_helper"
require "yast"

describe "discover_registration_services client" do
  before do
    # generic UI stubs for the progress dialog
    allow(Yast::UI).to receive(:GetDisplayInfo).and_return({})
    allow(Yast::UI).to receive(:BusyCursor)
    allow(Yast::UI).to receive(:NormalCursor)
    allow(Yast::UI).to receive(:OpenDialog)
    allow(Yast::UI).to receive(:CloseDialog)
  end

  context "when no SLP server is annnounced" do
    it "returns nil and does not ask the user" do
      expect(Yast::SlpService).to receive(:all).and_return([])
      expect(Yast::UI).to receive(:UserInput).never
      expect(Yast::WFM.call("discover_registration_services")).to be_nil
    end
  end

  context "when a SLP server is present" do
    # mocked announced registration URL via SLP
    let(:slp_url) { "https://example.com/register" }

    before do
      # stub the SLP service discovery
      slp_service = double
      slp_attributes = double
      allow(slp_attributes).to receive(:to_h).and_return(description: "Description")
      allow(slp_service).to receive(:attributes).and_return(slp_attributes)
      allow(slp_service).to receive(:slp_url).and_return("service:registration.suse:smt:#{slp_url}")
      allow(Yast::SlpService).to receive(:all).and_return([slp_service])
    end

    it "returns the SLP server selected by user" do
      # stub the user interaction in the SLP server selection dialog
      expect(Yast::UI).to receive(:UserInput).and_return(:ok)
      # the first radio button is selected
      expect(Yast::UI).to receive(:QueryWidget).and_return("0")

      expect(Yast::WFM.call("discover_registration_services")).to eq(slp_url)
    end

    it "returns nil when the SLP dialog is canceled" do
      # stub the user interaction in the SLP server selection dialog
      expect(Yast::UI).to receive(:UserInput).and_return(:ok)
      expect(Yast::UI).to receive(:QueryWidget).and_return("scc")

      expect(Yast::WFM.call("discover_registration_services")).to be_nil
    end
  end

end
