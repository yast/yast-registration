#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::MigrationReposWorkflow do
  describe "#run_sequence" do
    before do
      # Url of the registration server
      allow(Registration::UrlHelpers).to receive(:registration_url)
      allow(Registration::Addon).to receive(:find_all)
      allow(Registration::Registration).to receive(:is_registered?).and_return(true)
      # Load source information
      allow(Yast::Pkg).to receive(:SourceLoad)
      allow(Yast::Pkg).to receive(:SourceFinishAll)
      allow(Yast::Pkg).to receive(:SourceRestore)
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([])
      allow(Registration::SwMgmt).to receive(:check_repositories).and_return(true)
    end

    context "the system is not registered" do
      before do
        expect(Registration::Registration).to receive(:is_registered?).and_return(false)
        allow(Yast::Mode).to receive(:SetMode)
      end

      it "asks the user to register the system first" do
        expect(Yast::Popup).to receive(:ContinueCancel).and_return(false)
        subject.run_sequence
      end

      it "aborts when user does not want to continue" do
        expect(Yast::Popup).to receive(:ContinueCancel).and_return(false)
        expect(subject.run_sequence).to eq(:abort)
      end

      it "runs the full registration if user continues" do
        expect(Yast::Popup).to receive(:ContinueCancel).and_return(true)
        expect(Yast::WFM).to receive(:call).with("inst_scc")
        subject.run_sequence
      end

      it "aborts when the registration is aborted" do
        expect(Yast::Popup).to receive(:ContinueCancel).and_return(true)
        expect(Yast::WFM).to receive(:call).with("inst_scc").and_return(:abort)
        expect(subject.run_sequence).to eq(:abort)
      end
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
        expect(subject.run_sequence).to eq(:next)
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

      it "reports error and indicates needed rollback when upgrading a product fails" do
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

        expect(subject.run).to eq(:rollback)
      end
    end
  end
end
