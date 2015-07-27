#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::MigrationReposSelectionDialog do
  describe ".run" do
    before do
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([0, 1])
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(0).and_return(
        "name" => "name", "url" => "https://example.com", "enabled" => false)
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(1).and_return(
        "name" => "name2", "url" => "https://example2.com", "enabled" => true)

      # check the displayed content
      expect(Yast::Wizard).to receive(:SetContents) do |_title, content, _help, _back, _next|

        # do a simple check: convert the term to a String
        # an unselected repository
        expect(content.to_s).to include("item (`id (0), \"name (https://example.com)\", false)")
        # a selected repository
        expect(content.to_s).to include("`item (`id (1), \"name2 (https://example2.com)\", true)")
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

      expect(Yast::UI).to receive(:ChangeWidget)

      expect(subject.run).to eq(:abort)
    end
  end
end
