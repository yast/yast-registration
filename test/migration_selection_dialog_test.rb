#! /usr/bin/env rspec

require_relative "spec_helper"
include Yast::UIShortcuts

describe Registration::UI::MigrationSelectionDialog do
  subject { Registration::UI::MigrationSelectionDialog }
  let(:migration_products) { load_yaml_fixture("migration_to_sles12_sp1.yml") }

  describe ".run" do
    it "displays the possible migrations and returns the user input" do
      # user pressed the "Abort" button
      expect(Yast::UI).to receive(:UserInput).and_return(:abort)

      # check the displayed content
      expect(Yast::Wizard).to receive(:SetContents) do |_title, content, _help, _back, _next|
        # do a simple check: convert the term to a String
        expect(content.to_s).to include("`item (`id (0), \"SLES-12.1\")")
      end

      expect(subject.run(migration_products, [])).to eq(:abort)
    end

    it "saves the entered values when clicking Next" do
      expect(Yast::UI).to receive(:UserInput).and_return(:next)
      expect(Yast::UI).to receive(:QueryWidget).with(:migration_targets, :CurrentItem)
        .and_return(0).at_least(1)
      expect(Yast::UI).to receive(:QueryWidget).with(:manual_repos, :Value).and_return(true)

      dialog = subject.new(migration_products, [])
      expect(dialog.run).to eq(:next)

      # check the saved values
      expect(dialog.selected_migration).to eq(migration_products.first)
      expect(dialog.manual_repo_selection).to eq(true)
    end

    it "displays an error when the selected migration contains an unavailable product" do
      # user pressed the "Abort" button after displaying the error message
      expect(Yast::UI).to receive(:UserInput).and_return(:next, :abort)
      expect(Yast::UI).to receive(:QueryWidget).with(:migration_targets, :CurrentItem)
        .and_return(0).at_least(1)
      expect(Yast::Report).to receive(:Error)
        .with(/is not available at the registration server/)
      allow(Registration::UrlHelpers).to receive(:registration_url)
        .and_return("http://example.com")

      migrations = migration_products
      # make one product not available
      migrations.first.first.available = false

      dialog = subject.new(migrations, [])
      expect(dialog.run).to eq(:abort)
    end

    it "displays a product summary" do
      expect(Yast::UI).to receive(:UserInput).and_return(:next)
      expect(Yast::UI).to receive(:QueryWidget).with(:migration_targets, :CurrentItem)
        .and_return(0).at_least(1)
      expect(Yast::UI).to receive(:QueryWidget).with(:manual_repos, :Value).and_return(true)

      # load just the SLES12 product from that file
      installed = load_yaml_fixture("products_legacy_installation.yml")[1]

      dialog = subject.new(migration_products, [installed])
      expect(dialog.run).to eq(:next)
    end
  end
end
