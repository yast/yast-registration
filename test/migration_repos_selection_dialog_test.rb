#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/ui/migration_repos_selection_dialog"
require "registration/migration_repositories"

include Yast::UIShortcuts

describe Registration::UI::MigrationReposSelectionDialog do
  describe ".run" do
    before do
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([0, 1])
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(0).and_return(
        "name" => "name", "url" => "https://example.com", "enabled" => false
      )
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(1).and_return(
        "name" => "name2", "url" => "https://example2.com", "enabled" => true
      )
      allow(Yast::UI).to receive(:QueryWidget).with(:repos, :CurrentItem).and_return(0)

      # check the displayed content
      expect(Yast::Wizard).to receive(:SetContents) do |_title, content, _help, _back, _next|
        term = content.nested_find do |t|
          t.respond_to?(:value) && t.value == :MultiSelectionBox &&
            t.params[3].include?(Item(Id(0), "name", false)) &&
            t.params[3].include?(Item(Id(1), "name2", true))
        end

        expect(term).to_not eq(nil)
      end
    end

    it "displays the configured repositories and returns the user input" do
      # user pressed the "Abort" button
      expect(Yast::UI).to receive(:UserInput).and_return(:abort)
      expect(subject.run).to eq(:abort)
    end

    it "configures the selected repositories for distribution upgrade" do
      # user pressed the "Next" button
      expect(Yast::UI).to receive(:UserInput).and_return(:next)
      expect(Yast::UI).to receive(:QueryWidget).with(:repos, :SelectedItems).and_return([1])
      # resets the repositories
      expect(Registration::MigrationRepositories).to receive(:reset)
      # activates the new config
      expect_any_instance_of(Registration::MigrationRepositories).to receive(:activate_repositories)

      expect(subject.run).to eq(:next)
    end

    it "starts the repository manager when the respective button is pressed" do
      # start repo management, abort after returning back
      expect(Yast::UI).to receive(:UserInput).and_return(:repo_mgmt, :abort)
      expect(Yast::WFM).to receive(:call).with("repositories", ["refresh-enabled"])
        .and_return(:next)

      expect(Yast::UI).to receive(:ChangeWidget).twice
      expect(subject).to receive(:store_values)

      expect(subject.run).to eq(:abort)
    end
  end
end
