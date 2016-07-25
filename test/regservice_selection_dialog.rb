require_relative "spec_helper"
require "registration/ui/regservice_selection_dialog"

Yast.import "SlpService"

describe Registration::UI::RegserviceSelectionDialog do
  include Yast::UIShortcuts

  subject(:dialog) { Registration::UI::RegserviceSelectionDialog.new(services: services) }

  before do
    allow(Yast::UI).to receive(:OpenDialog).and_return(true)
    allow(Yast::UI).to receive(:CloseDialog).and_return(true)
  end

  let(:services) do
    [
      Yast::SlpServiceClass::Service.new(
        name: "smt1",
        data: { "pcSrvType" => "smt", "srvurl" => "http://smt1.example.net" }
      ),
      Yast::SlpServiceClass::Service.new(
        name: "smt2",
        data: { "pcSrvType" => "smt", "srvurl" => "http://smt2.example.net" }
      )
    ]
  end

  before do
    allow(Yast::SlpServiceClass::DnsCache).to receive(:resolve)
      .and_return("somehost")
    allow(Yast::SLP).to receive(:GetUnicastAttrMap)
      .and_return(type: "server", description: "SMT")
  end

  describe "#run" do
    context "when the OK button is pressed" do
      before do
        expect(Yast::UI).to receive(:QueryWidget).with(Id(:services), :CurrentButton)
          .and_return(selected)
        allow(Yast::UI).to receive(:UserInput).and_return(:ok)
      end

      context "when 'scc' option is selected" do
        let(:selected) { "0" }

        it "returns :scc" do
          expect(dialog.run).to eq(:scc)
        end
      end

      context "when a service is selected" do
        let(:selected) { "1" }

        it "returns the selected service" do
          expect(dialog.run).to eq(services.first)
        end
      end

      context "when no option is selected" do
        let(:selected) { nil }

        it "shows an error" do
          expect(Yast::UI).to receive(:UserInput).and_return(:ok, :cancel)
          expect(Yast::Report).to receive(:Error).and_return(true)
          dialog.run
        end
      end
    end

    context "when the cancel button is pressed" do
      it "returns :cancel" do
        expect(Yast::UI).to receive(:UserInput).and_return(:cancel)
        expect(dialog.run).to eq(:cancel)
      end
    end

    it "sets default heading and description" do
      expect(Yast::UI).to receive(:UserInput).and_return(:cancel)
      expect(dialog).to receive(:Heading)
        .with(_("Local Registration Servers"))
      expect(dialog).to receive(:Label)
        .with(_("Select a detected registration server " \
        "from the list\nor the default SUSE registration server."))
      dialog.run
    end

    context "when customized heading/description are specified" do
      subject(:dialog) do
        Registration::UI::RegserviceSelectionDialog.new(
          services: services, heading: "some title", description: "some description"
          )
      end

      it "sets heading and description accordingly" do
        expect(Yast::UI).to receive(:UserInput).and_return(:cancel)
        expect(dialog).to receive(:Heading).with("some title")
        expect(dialog).to receive(:Label).with("some description")
        dialog.run
      end
    end
  end
end
