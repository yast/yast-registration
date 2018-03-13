#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::OfflineMigrationWorkflow do
  describe "#main" do
    it "runs the 'inst_migration_repos' client" do
      expect(Yast::WFM).to receive(:CallFunction).with("inst_migration_repos", anything)
      subject.main
    end

    it "returns the 'inst_migration_repos' result" do
      expect(Yast::WFM).to receive(:CallFunction).with("inst_migration_repos", anything)
        .and_return(:foo)
      expect(subject.main).to eq(:foo)
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
