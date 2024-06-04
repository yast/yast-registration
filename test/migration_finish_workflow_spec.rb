#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/ui/migration_finish_workflow"

describe Registration::UI::MigrationFinishWorkflow do
  describe "#run_sequence" do
    it "restores the repository setup and returns :next" do
      expect_any_instance_of(Registration::RepoStateStorage).to receive(:restore_all)
      expect(subject.run_sequence).to eq(:next)
    end
  end
end
