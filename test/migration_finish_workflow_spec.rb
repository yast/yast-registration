#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::MigrationFinishWorkflow do
  describe ".run" do
    subject { Registration::UI::MigrationFinishWorkflow }

    before do
      allow_any_instance_of(Registration::RepoStateStorage).to receive(:read)
    end

    it "restores the repository setup and returns :next" do
      expect_any_instance_of(Registration::RepoStateStorage).to receive(:restore_all)
      expect(subject.run).to eq(:next)
    end

    it "returns :abort on an error" do
      allow_any_instance_of(Registration::RepoStateStorage).to receive(:restore_all)
      msg = "Something failed..."
      expect(Yast::Sequencer).to receive(:Run).and_raise(msg)
      expect(subject.run).to eq(:abort)
    end

  end
end
