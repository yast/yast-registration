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
      allow(Yast::Stage).to receive(:initial).and_return(false)
      allow(Yast::Mode).to receive(:update).and_return(false)
      allow(Yast::Linuxrc).to receive(:InstallInf)
      allow(Y2Packager::MediumType).to receive(:offline?).and_return(false)
      allow(Y2Packager::MediumType).to receive(:online?).and_return(false)
      allow(Yast::Report).to receive(:Error)
    end

    shared_examples "media based upgrade" do |popup_method|
      before do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("MediaUpgrade").and_return("1")
      end

      it "displays a popup about media based upgrade" do
        if popup_method == :LongMessageGeometry
          expect(Yast::Popup).to receive(popup_method).with(/media based upgrade/i,
            anything, anything)
        else
          expect(Yast::Popup).to receive(popup_method).with(/media based upgrade/i)
        end
        subject.run_sequence
      end

      it "returns :next symbol" do
        expect(subject.run_sequence).to eq(:next)
      end
    end

    context "the system is registered" do
      before do
        allow(Registration::Registration).to receive(:is_registered?).and_return(true)
        allow(Yast::Mode).to receive(:SetMode)
      end

      context "at system upgrade" do
        before do
          allow(Yast::Stage).to receive(:initial).and_return(true)
          allow(Yast::Mode).to receive(:update).and_return(true)
          allow(Yast::Popup).to receive(:LongMessage)
        end

        context "the 'media_upgrade=1' boot parameter is used" do
          include_examples "media based upgrade", :LongMessageGeometry
        end
      end
    end

    context "the system is not registered" do
      before do
        allow(Registration::Registration).to receive(:is_registered?).and_return(false)
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

      context "at system upgrade" do
        before do
          allow(Yast::Stage).to receive(:initial).and_return(true)
          allow(Yast::Mode).to receive(:update).and_return(true)
          allow(Yast::Popup).to receive(:LongMessage)
          allow(Yast::SourceDialogs).to receive(:display_addon_checkbox=)
          allow(Yast::SourceDialogs).to receive(:SetURL)
        end

        it "displays a popup about unregistered system" do
          expect(Yast::Popup).to receive(:LongMessage).with(/unregistered system/i)
          subject.run_sequence
        end

        it "preselects a dvd:// add-on repository to be added later" do
          expect(Yast::SourceDialogs).to receive(:display_addon_checkbox=).with(false)
          expect(Yast::SourceDialogs).to receive(:SetURL).with("dvd://")
          subject.run_sequence
        end

        it "returns :next symbol" do
          expect(subject.run_sequence).to eq(:next)
        end

        context "the 'media_upgrade=1' boot parameter is used" do
          include_examples "media based upgrade", :LongMessage
        end
      end
    end

    context "if package management initialization succeeds" do
      let(:migrations) { load_yaml_fixture("migration_to_sles12_sp1.yml") }
      let(:migration_service) { load_yaml_fixture("migration_service.yml") }

      before do
        expect(Registration::SwMgmt).to receive(:init).at_least(1)
        allow_any_instance_of(Registration::RepoStateStorage).to receive(:write)
        allow_any_instance_of(Registration::RollbackScript).to receive(:create)
        allow(Yast::Report).to receive(:Error)
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

      it "selects products to install" do
        set_success_expectations
        expect(Registration::SwMgmt).to receive(:select_addon_products) do |services|
          expect(services.first.id).to eq(1311)
        end

        subject.run_sequence
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
        allow(Registration::SwMgmt).to receive(:installed_products)
          .and_return([])
        expect(Yast::Report).to receive(:Error)

        expect(subject.run).to eq(:abort)
      end

      it "reports error and aborts when no migration is available" do
        # installed SLES12
        allow(Registration::SwMgmt).to receive(:installed_products)
          .and_return([load_yaml_fixture("products_legacy_installation.yml")[1]])
        expect_any_instance_of(Registration::RegistrationUI).to receive(:migration_products)
          .and_return([])
        expect(Yast::Report).to receive(:Error).at_least(:once)

        expect(subject.run).to eq(:abort)
      end

      it "reports error and indicates needed rollback when upgrading a product fails" do
        expect(Yast::Report).to receive(:Error)
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

  describe "#load_migration_products_offline" do
    let(:activated_products) { load_yaml_fixture("migration_sles15_activated_products.yml") }
    let(:offline_migrations) { load_yaml_fixture("migration_sles15_offline_migrations.yml") }
    let(:selected_base) { load_yaml_fixture("migration_sles15_selected_base.yml") }

    before do
      allow(Y2Packager::ProductUpgrade).to receive(:new_base_product).and_return(selected_base)
      allow_any_instance_of(Registration::RegistrationUI).to receive(:offline_migration_products)
        .and_return(offline_migrations)

      allow(Yast::Pkg).to receive(:PkgUpdateAll)
      allow(Yast::Pkg).to receive(:PkgReset)
      allow(Yast::Pkg).to receive(:GetPackages).and_return([])

      # skip SLP discovery
      allow(Registration::UrlHelpers).to receive(:registration_url)
    end

    context "no migration product found" do
      before do
        expect(Y2Packager::ProductUpgrade).to receive(:new_base_product).and_return(nil)
        allow(Yast::Report).to receive(:Error)
      end

      it "displays a warning popup" do
        expect(Yast::Report).to receive(:Error).with(/Cannot find a base product/)
        subject.send(:load_migration_products_offline, activated_products)
      end

      it "returns :empty" do
        ret = subject.send(:load_migration_products_offline, activated_products)
        expect(ret).to eq(:empty)
      end
    end

    it "loads the possible migrations from the server" do
      subject.send(:load_migration_products_offline, activated_products)
      expect(subject.send(:migrations)).to_not be_empty
    end

    it "asks for confirmation if the system was already migrated" do
      # pretend SLES15 is already activated
      sles15 = OpenStruct.new(
        arch:       "x86_64",
        identifier: "SLES",
        version:    "15"
      )
      activated_products2 = [sles15]

      expect(Yast2::Popup).to receive(:show).with(/is already activated/,
        buttons: :continue_cancel, focus: :cancel)
      subject.send(:load_migration_products_offline, activated_products2)
    end

    it "returns :next if a migration is found" do
      expect(subject.send(:load_migration_products_offline, activated_products)).to eq(:next)
    end

    it "returns :empty if no migration is found" do
      allow_any_instance_of(Registration::RegistrationUI).to receive(:offline_migration_products)
        .and_return([])
      allow(Yast::Report).to receive(:Error)

      subject.send(:load_migration_products_offline, activated_products)
    end
  end
end
