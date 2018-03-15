#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::OfflineMigrationWorkflow do
  describe "#main" do
    before do
      allow(Yast::Wizard).to receive(:ClearContents)
      allow(Yast::Packages).to receive(:init_called=)
      allow(Yast::Packages).to receive(:Initialize)
      allow(Yast::GetInstArgs).to receive(:going_back)
      allow(File).to receive(:delete)
      allow(Yast::WFM).to receive(:CallFunction)
    end

    context "when going back" do
      before do
        expect(Yast::GetInstArgs).to receive(:going_back).and_return(true)
        allow(Registration::Registration).to receive(:is_registered?)
      end

      it "returns :back" do
        expect(subject.main).to eq(:back)
      end

      it "does not run rollback when the system is not registered" do
        expect(subject).to_not receive(:rollback)
        subject.main
      end

      context "the system is registered" do
        before do
          expect(Registration::Registration).to receive(:is_registered?).and_return(true)
          allow(Yast::WFM).to receive(:CallFunction).with("registration_sync")
        end

        it "runs rollback" do
          expect(Yast::WFM).to receive(:CallFunction).with("registration_sync")
          subject.main
        end

        it "removes the copied credentials" do
          expect(Yast::Stage).to receive(:initial).and_return(true)
          # allow the other cases
          allow(File).to receive(:exist?)
          expect(File).to receive(:exist?).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
            .and_return(true)
          expect(File).to receive(:delete).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
          subject.main
        end
      end
    end

    it "runs the 'inst_migration_repos' client" do
      expect(Yast::WFM).to receive(:CallFunction).with("inst_migration_repos", anything)
      subject.main
    end

    it "returns the 'inst_migration_repos' result" do
      expect(Yast::WFM).to receive(:CallFunction).with("inst_migration_repos", anything)
        .and_return(:foo)
      expect(subject.main).to eq(:foo)
    end

    describe "it updates the add-on records" do
      let(:new_id) { 23 }
      let(:product_dir) { "" }
      let(:url) { "dir:///update/000/repo" }

      before do
        expect(Yast::Pkg).to receive(:SourceGetCurrent).and_return([new_id])
        expect(Yast::Pkg).to receive(:SourceGeneralData).with(new_id).and_return(
          "url"         => url,
          "product_dir" => product_dir
        )
      end

      it "updates the repository ID" do
        addons = [
          {
            "media_url"   => url,
            "media"       => 42,
            "product_dir" => product_dir,
            "product"     => "Driver Update 0"
          }
        ]

        Yast::AddOnProduct.add_on_products = addons

        expect { subject.main }.to change { Yast::AddOnProduct.add_on_products.first["media"] }
          .from(42).to(new_id)
      end

      it "ignores the alias query in the addon URL" do
        url2 = "dir:///update/000/repo?alias=DriverUpdate0"

        addons = [
          {
            "media_url"   => url2,
            "media"       => 42,
            "product_dir" => product_dir,
            "product"     => "Driver Update 0"
          }
        ]

        Yast::AddOnProduct.add_on_products = addons

        expect { subject.main }.to change { Yast::AddOnProduct.add_on_products.first["media"] }
          .from(42).to(new_id)
      end
    end

    context "the 'inst_migration_repos' client returns :rollback" do
      before do
        expect(Yast::WFM).to receive(:CallFunction).with("inst_migration_repos", anything)
          .and_return(:rollback)
        allow(Yast::WFM).to receive(:CallFunction).with("registration_sync")
      end

      it "runs the 'registration_sync' client" do
        expect(Yast::WFM).to receive(:CallFunction).with("registration_sync")
        subject.main
      end

      it "return :back" do
        expect(subject.main).to eq(:back)
      end
    end
  end
end
