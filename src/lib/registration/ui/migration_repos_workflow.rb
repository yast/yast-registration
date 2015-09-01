# ------------------------------------------------------------------------------
# Copyright (c) 2015 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# ------------------------------------------------------------------------------
#

require "yast"

require "registration/registration"
require "registration/registration_ui"
require "registration/migration_repositories"
require "registration/sw_mgmt"
require "registration/ui/migration_selection_dialog"
require "registration/ui/migration_repos_selection_dialog"

module Registration
  module UI
    # This class handles workflow for adding migration services
    class MigrationReposWorkflow
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts

      Yast.import "Report"
      Yast.import "Sequencer"

      # run workflow for adding the migration services
      # @return [Symbol] the UI symbol
      def self.run
        workflow = MigrationReposWorkflow.new
        workflow.run
      end

      # the constructor
      def initialize
        textdomain "registration"

        # a dummy message which will be used later, just make sure we have it
        # before the translation deadline...
        # TRANSLATORS: popup question, confirm installing the available
        # updates now
        _("Online updates are available for installation.\n" \
            "It is recommended to install all updates before proceeding.\n\n" \
            "Would you like to install the updates now?")

        url = UrlHelpers.registration_url
        self.registration = Registration.new(url)
        self.registration_ui = RegistrationUI.new(registration)
        self.registered_services = []
      end

      # The repositories migration workflow is:
      #
      # - find all installed products
      # - query registered addons from the server
      # - ask the registration server for the available product migrations
      #   (for both installed and registered products)
      # - user selects the migration target
      # - the registered products are upgraded and new services/repositories
      #   are added to the system
      # - (optionally) user manually selects the migration repositories
      # - user is asked to install also the latest updates (or to migrate to the GA version)
      # - "Update from ALL" is set in libzypp (uses all enabled repositories)
      # - (optional step) user can manually set the migration repositories,
      #   the selected repositories are enabled or disabled
      # - return the user input symbol (:next or :abort) to the caller
      # @return [Symbol] the UI symbol
      #
      def run
        log.info "Starting migration repositories sequence"

        ret = nil
        begin
          ret = run_sequence
        rescue => e
          log.error "Caught error: #{e.class}: #{e.message.inspect}, #{e.backtrace}"
          # TRANSLATORS: error message, %s are details
          Yast::Report.Error(_("Internal error: %s") % e.message)
          ret = :abort
        end

        ret
      end

      private

      attr_accessor :products, :migrations, :registration,
        :registration_ui, :selected_migration, :registered_services,
        :manual_repo_selection

      WORKFLOW_SEQUENCE = {
        "ws_start"                    => "find_products",
        "find_products"               => {
          abort:  :abort,
          cancel: :abort,
          next:   "load_migration_products"
        },
        "load_migration_products"     => {
          abort:  :abort,
          cancel: :abort,
          next:   "select_migration_products"
        },
        "select_migration_products"   => {
          abort:  :abort,
          cancel: :abort,
          next:   "register_migration_products"
        },
        "register_migration_products" => {
          abort:  :abort,
          cancel: :abort,
          next:   "activate_migration_repos"
        },
        "activate_migration_repos"    => {
          abort:          :abort,
          cancel:         :abort,
          repo_selection: "select_migration_repos",
          next:           "store_repos_state"
        },
        "select_migration_repos"      => {
          abort:  :abort,
          cancel: :abort,
          next:   "store_repos_state"
        },
        "store_repos_state"           => {
          next: :next
        }
      }

      # run the workflow
      # @return [Symbol] the UI symbol
      def run_sequence
        aliases = {
          "find_products"               => [->() { find_products }, true],
          "load_migration_products"     => [->() { load_migration_products }, true],
          "select_migration_products"   => ->() { select_migration_products },
          "register_migration_products" => [->() { register_migration_products }, true],
          "activate_migration_repos"    => [->() { activate_migration_repos }, true],
          "select_migration_repos"      => ->() { select_migration_repos },
          "store_repos_state"           => ->() { store_repos_state }
        }

        ui = Yast::Sequencer.Run(aliases, WORKFLOW_SEQUENCE)
        log.info "User input: #{ui}"
        ui
      end

      # find all installed products
      # @return [Symbol] workflow symbol (:next or :abort)
      def find_products
        log.info "Loading installed products"

        if !SwMgmt.init(true)
          Yast::Report.Error(Yast::Pkg.LastError)
          return :abort
        end

        self.products = ::Registration::SwMgmt.installed_products.map do |product|
          ::Registration::SwMgmt.remote_product(product)
        end

        if products.empty?
          # TRANSLATORS: Error message
          Yast::Report.Error(_("No installed product found."))
          return :abort
        end

        merge_registered_addons
        log.info "Products to migrate: #{products}"

        :next
      end

      def merge_registered_addons
        # load the extensions to merge the registered but not installed extensions
        Addon.find_all(registration)

        addons = Addon.registered_not_installed.map(&:to_h).map do |addon|
          SwMgmt.remote_product(addon)
        end

        products.concat(addons)
      end

      # load migration products for the installed products from the registration server
      # @return [Symbol] workflow symbol (:next or :abort)
      def load_migration_products
        log.info "Loading migration products from server"
        self.migrations = registration_ui.migration_products(products)

        if migrations.empty?
          # TRANSLATORS: Error message
          Yast::Report.Error(_("No migration product found."))
          return :abort
        end

        :next
      end

      # run the migration target selection dialog
      # @return [Symbol] workflow symbol (:next or :abort)
      def select_migration_products
        log.info "Displaying migration target selection dialog"
        dialog = MigrationSelectionDialog.new(migrations, products_to_migrate)
        ret = dialog.run

        if ret == :next
          self.selected_migration = dialog.selected_migration
          self.manual_repo_selection = dialog.manual_repo_selection
          log.info "Selected migration: #{selected_migration}"
        end

        ret
      end

      # collect products to migrate
      # @return [Array<Hash>] installed or registered products
      def products_to_migrate
        installed_products = SwMgmt.installed_products
        log.info "installed_products: #{installed_products}"

        registered_products = Addon.registered_not_installed.map do |addon|
          ret = addon.to_h
          ret["display_name"] = addon.friendly_name
          ret
        end

        installed_products.concat(registered_products)
      end

      # upgrade the services to the new version
      # @return [Symbol] workflow symbol (:next)
      def register_migration_products
        migration_progress

        begin
          log.info "Registering the migration target products"
          Yast::Popup.Feedback(RegistrationUI::CONTACTING_MESSAGE,
            # TRANSLATORS: Progress label
            _("Registering Migration Products...")) do
            if !selected_migration.all? { |product| register_migration_product(product) }
              return :abort
            end
          end
        ensure
          Yast::Wizard.EnableNextButton
          Yast::Wizard.EnableBackButton
        end

        # synchronize the changes done by modifying the services,
        # reinitialize the repositories and reload the available packages
        Yast::Pkg.SourceFinishAll
        Yast::Pkg.TargetFinish
        SwMgmt.init(true)

        log.info "Registered services: #{registered_services}"
        :next
      end

      # just set an empty Wizard dialog to replace the current one after
      # pressing "Next"
      def migration_progress
        Yast::Wizard.SetContents(
          _("Registration"),
          # TRANSLATORS: progress message
          Label(_("Preparing Migration Repositories...")),
          "",
          false,
          false
        )
      end

      # register a migration product
      # @return [Boolean] true on success
      def register_migration_product(product)
        log.info "Registering migration product #{product}"

        ConnectHelpers.catch_registration_errors do
          registered_services << registration.upgrade_product(product)
        end
      end

      # activate the added migration repos (set the DUP property)
      # @return [Symbol] the UI symbol (:abort, :next or :repo_selection)
      def activate_migration_repos
        log.info "Activating the migration repositories"
        migration_repos = ::Registration::MigrationRepositories.new
        registered_services.each do |service|
          migration_repos.services << service
        end

        if migration_repos.service_with_update_repo?
          migration_repos.install_updates = registration_ui.install_updates?
        end

        migration_repos.activate_services

        manual_repo_selection ? :repo_selection : :next
      end

      # run the manual migration repository selection dialog
      # @return [Symbol] the UI symbol (:abort, :next)
      def select_migration_repos
        UI::MigrationReposSelectionDialog.run
      end

      def store_repos_state
        RepoStateStorage.instance.write
        :next
      end
    end
  end
end
