#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/ui/abort_confirmation"

Yast.import "Popup"
Yast.import "Mode"

describe Registration::UI::AbortConfirmation do
  describe ".run" do
    subject(:run) { Registration::UI::AbortConfirmation.run }

    before do
      allow(Yast::Mode).to receive(:installation).and_return installation
    end

    context "during installation" do
      let(:installation) { true }

      it "returns the result of Popup.ConfirmAbort" do
        expect(Yast::Popup).to receive(:ConfirmAbort).and_return "user decision"
        expect(run).to eq "user decision"
      end
    end

    context "during update or normal execution" do
      let(:installation) { false }

      it "returns the result of Popup.AnyQuestion" do
        expect(Yast::Popup).to receive(:AnyQuestion).and_return "user decision"
        expect(run).to eq "user decision"
      end
    end
  end
end
