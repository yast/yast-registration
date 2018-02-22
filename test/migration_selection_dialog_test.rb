#! /usr/bin/env rspec

require_relative "spec_helper"
include Yast::UIShortcuts

describe Registration::UI::MigrationSelectionDialog do
  subject { Registration::UI::MigrationSelectionDialog }
  let(:migration_products) { load_yaml_fixture("migration_to_sles12_sp1.yml") }
  let(:migration_products_sle15) { load_yaml_fixture("migration_sles15_offline_migrations.yml") }

  describe ".run" do
    it "displays the possible migrations and returns the user input" do
      # user pressed the "Abort" button
      expect(Yast::UI).to receive(:UserInput).and_return(:abort)

      # check the displayed content
      expect(Yast::Wizard).to receive(:SetContents) do |_title, content, _help, _back, _next|
        expected_list_item = Item(Id(0), "SLES12-SP1")

        term = content.nested_find do |t|
          t.respond_to?(:value) && t.value == :SelectionBox &&
            t.params[3].include?(expected_list_item)
        end

        expect(term).to_not eq(nil)
      end

      expect(subject.run(migration_products, [])).to eq(:abort)
    end

    it "handles product renames in the summary" do
      # user pressed the "Abort" button, just to get out of the event loop
      allow(Yast::UI).to receive(:UserInput).and_return(:abort)
      allow(Yast::Wizard).to receive(:SetContents)
      # the first migration is selected
      expect(Yast::UI).to receive(:QueryWidget).with(:migration_targets, :CurrentItem).and_return(0)
      # check the correct summary
      expect(Yast::UI).to receive(:ChangeWidget) do |_id, _attr, text|
        # SLES11 uses "SUSE_SLES" product identifier while SLES15 uses just "SLES",
        # the summary needs to mention a product upgrade although technically these
        # are different products with different statuses ("SUSE_SLES" will be uninstalled,
        # "SLES" will be installed)
        expect(text).to include("SUSE Linux Enterprise Server 11 SP4 <b>will be " \
          "upgraded to</b> SUSE Linux Enterprise Server 15")
      end

      sles11sp4 = load_yaml_fixture("installed_sles11-sp4_products.yml")
      subject.run(migration_products_sle15, sles11sp4)
    end

    it "handles product merges in the summary" do
      # user pressed the "Abort" button, just to get out of the event loop
      allow(Yast::UI).to receive(:UserInput).and_return(:abort)
      allow(Yast::Wizard).to receive(:SetContents)
      # the first migration is selected
      expect(Yast::UI).to receive(:QueryWidget).with(:migration_targets, :CurrentItem).and_return(0)
      # check the correct summary
      expect(Yast::UI).to receive(:ChangeWidget) do |_id, _attr, text|
        # For SLE15 there are two products (SDK and Toolchain Module) replaced
        # by single product (Development Tools Module)
        expect(text).to include("SUSE Linux Enterprise Software Development Kit 12 SP3 "\
          "<b>will be upgraded to</b> Development Tools Module 15")
        expect(text).to include("Toolchain Module <b>will be upgraded to</b> " \
          "Development Tools Module 15")
      end

      sles12sp3 = load_yaml_fixture("installed_sles12-sp3_products.yml")
      subject.run(migration_products_sle15, sles12sp3)
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
