#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::MigrationReposWorkflow do
  describe ".run" do
    subject { Registration::UI::MigrationReposWorkflow }

    before do
      # Url of the registration server
      allow(Registration::UrlHelpers).to receive(:registration_url)
      allow(Registration::Addon).to receive(:find_all)
      # Load source information
      allow(Yast::Pkg).to receive(:SourceLoad)
      allow(Yast::Pkg).to receive(:SourceFinishAll)
      allow(Yast::Pkg).to receive(:SourceRestore)
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([])
    end

    it "aborts if package management initialization fails" do
      msg = "Initialization failed"
      expect(Registration::SwMgmt).to receive(:init).and_raise(Registration::PkgError, msg)

      expect(subject.run).to eq(:abort)
    end

    it "handles any exception raised and reports an error" do
      msg = "Something failed..."
      expect(Yast::Sequencer).to receive(:Run).and_raise(msg)

      expect(subject.run).to eq(:abort)
    end

    context "if package management initialization succeeds" do
      let(:migrations) { load_yaml_fixture("migration_to_sles12_sp1.yml") }
      let(:migration_service) { load_yaml_fixture("migration_service.yml") }

      before do
        expect(Registration::SwMgmt).to receive(:init).at_least(1)
        allow_any_instance_of(Registration::RepoStateStorage).to receive(:write)
      end

      let(:set_success_expectations) do
        # installed SLES12
        allow(Registration::SwMgmt).to receive(:installed_products)
          .and_return([load_yaml_fixture("products_legacy_installation.yml")[1]])

        expect_any_instance_of(Registration::RegistrationUI).to receive(:migration_products)
          .and_return(migrations)

        # user selected a migration and pressed [Next]
        expect_any_instance_of(Registration::UI::MigrationSelectionDialog).to receive(:run)
          .and_return(:next)
        expect_any_instance_of(Registration::UI::MigrationSelectionDialog).to \
          receive(:selected_migration).and_return(migrations.first)

        expect_any_instance_of(Registration::Registration).to receive(:upgrade_product)
          .and_return(migration_service)

        expect_any_instance_of(Registration::MigrationRepositories).to receive(:activate_services)
      end

      it "registers the selected migration products" do
        set_success_expectations
        expect(subject.run).to eq(:next)
      end

      it "displays the custom repository selection if required" do
        set_success_expectations

        # repository selection dialog
        expect_any_instance_of(Registration::UI::MigrationSelectionDialog).to \
          receive(:manual_repo_selection).and_return(true)
        expect_any_instance_of(Registration::UI::MigrationReposSelectionDialog).to \
          receive(:run).and_return(:next)

        expect(subject.run).to eq(:next)
      end

      it "does not install updates if not required" do
        set_success_expectations

        # an update available
        expect_any_instance_of(Registration::MigrationRepositories).to \
          receive(:service_with_update_repo?).and_return(true)
        # user requestes skipping updates
        expect_any_instance_of(Registration::RegistrationUI).to receive(:install_updates?)
          .and_return(false)

        # make sure the updates are disabled
        expect_any_instance_of(Registration::MigrationRepositories).to \
          receive(:install_updates=).with(false)
        expect(subject.run).to eq(:next)
      end

      it "reports error and aborts when no installed product is found" do
        expect(Registration::SwMgmt).to receive(:installed_products)
          .and_return([])
        expect(Yast::Report).to receive(:Error)

        expect(subject.run).to eq(:abort)
      end

      it "reports error and aborts when no migration is available" do
        # installed SLES12
        expect(Registration::SwMgmt).to receive(:installed_products)
          .and_return([load_yaml_fixture("products_legacy_installation.yml")[1]])
        expect_any_instance_of(Registration::RegistrationUI).to receive(:migration_products)
          .and_return([])
        expect(Yast::Report).to receive(:Error)

        expect(subject.run).to eq(:abort)
      end

      it "reports error and aborts when registering the migration products fails" do
        # installed SLES12
        allow(Registration::SwMgmt).to receive(:installed_products)
          .and_return([load_yaml_fixture("products_legacy_installation.yml")[1]])

        expect_any_instance_of(Registration::RegistrationUI).to receive(:migration_products)
          .and_return(migrations)

        # user selected a migration and pressed [Next]
        expect_any_instance_of(Registration::UI::MigrationSelectionDialog).to receive(:run)
          .and_return(:next)
        expect_any_instance_of(Registration::UI::MigrationSelectionDialog).to \
          receive(:selected_migration).and_return(migrations.first)

        expect_any_instance_of(Registration::Registration).to receive(:upgrade_product)
          .and_raise("Registration failed")

        expect(subject.run).to eq(:abort)
      end
    end
  end
end
