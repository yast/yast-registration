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
require "registration/releasever"
require "registration/sw_mgmt"
require "registration/url_helpers"
require "registration/ui/wizard_client"
require "registration/ui/migration_selection_dialog"
require "registration/ui/migration_repos_selection_dialog"
require "registration/ui/not_installed_products_dialog"

module Registration
  module UI
    # This class handles workflow for adding migration services
    class MigrationReposWorkflow < WizardClient
      include Yast::UIShortcuts

      Yast.import "Sequencer"
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "SourceDialogs"
      Yast.import "Linuxrc"

      # the constructor
      def initialize
        textdomain "registration"

        url = UrlHelpers.registration_url
        self.registration = Registration.new(url)
        self.registration_ui = RegistrationUI.new(registration)
        self.registered_services = []
      end

      # The repositories migration workflow is:
      #
      # - if the system is not registered ask the user to register it first
      #   (otherwise abort the online migration)
      # - check registered but not installed products allowing the user to
      #   syncronize them (skipped in case of not found)
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
      def run_sequence
        log.info "Starting migration repositories sequence"

        aliases = {
          "registration_check"           => [->() { registration_check }, true],
          "not_installed_products_check" => [->() { not_installed_products_check }, true],
          "find_products"                => [->() { find_products }, true],
          "load_migration_products"      => [->() { load_migration_products }, true],
          "select_migration_products"    => ->() { select_migration_products },
          "update_releasever"            => ->() { update_releasever },
          "register_migration_products"  => [->() { register_migration_products }, true],
          "activate_migration_repos"     => [->() { activate_migration_repos }, true],
          "select_migration_repos"       => ->() { select_migration_repos },
          "store_repos_state"            => ->() { store_repos_state }
        }

        ui = Yast::Sequencer.Run(aliases, WORKFLOW_SEQUENCE)
        log.info "User input: #{ui}"
        ui
      end

    private

      attr_accessor :products, :migrations, :registration,
        :registration_ui, :selected_migration, :registered_services,
        :manual_repo_selection

      WORKFLOW_SEQUENCE = {
        "ws_start"                     => "registration_check",
        "registration_check"           => {
          abort: :abort,
          skip:  :next,
          next:  "not_installed_products_check"
        },
        "not_installed_products_check" => {
          abort:  :abort,
          cancel: :abort,
          next:   "find_products"
        },
        "find_products"                => {
          abort:  :abort,
          cancel: :abort,
          next:   "load_migration_products"
        },
        "load_migration_products"      => {
          abort:  :abort,
          cancel: :abort,
          empty:  :back,
          next:   "select_migration_products"
        },
        "select_migration_products"    => {
          abort:  :abort,
          cancel: :abort,
          next:   "update_releasever"
        },
        "update_releasever"            => {
          next: "register_migration_products"
        },
        "register_migration_products"  => {
          abort:  :rollback,
          cancel: :rollback,
          next:   "activate_migration_repos"
        },
        "activate_migration_repos"     => {
          abort:          :rollback,
          cancel:         :rollback,
          repo_selection: "select_migration_repos",
          next:           "store_repos_state"
        },
        "select_migration_repos"       => {
          abort:  :rollback,
          cancel: :rollback,
          next:   "store_repos_state"
        },
        "store_repos_state"            => {
          next: :next
        }
      }.freeze

      # check whether the system is registered, ask the user to register it
      # if the system is not registered
      # @return [Symbol] workflow symbol, :next if registered, :abort when not
      def registration_check
        # handle system upgrade (fate#323163)
        if Yast::Stage.initial && Yast::Mode.update
          log.info "System upgrade mode detected"
          return system_upgrade_check
        end

        return :next if Registration.is_registered?

        # TRANSLATORS: a popup message with [Continue] [Cancel] buttons,
        # pressing [Continue] starts the registration module, [Cancel] aborts
        # the online migration
        register = Yast::Popup.ContinueCancel(_("The system is not registered,\n" \
              "to run the online migration you need\n" \
              "to register the system first."))

        return :abort unless register

        register_system
      end

      # run the registration module to register the system
      # @return [Symbol] the registration result
      def register_system
        # temporarily switch back to the normal mode so the registration behaves as expected
        mode = Yast::Mode.mode
        log.info "Setting 'normal' mode"
        Yast::Mode.SetMode("normal")

        ret = Yast::WFM.call("inst_scc")
        log.info "Registration result: #{ret.inspect}"

        log.info "Restoring #{mode.inspect} mode"
        Yast::Mode.SetMode(mode)
        ret
      end

      def not_installed_products_check
        SwMgmt.init(true)

        # FIXME: do the check also at offline upgrade?
        # Currently it reads the addons for the new SLES15 which is not
        # registered yet and fails.
        return :next if Yast::Stage.initial

        Addon.find_all(registration)

        UI::NotInstalledProductsDialog.run
      end

      # find all installed products
      # @return [Symbol] workflow symbol (:next or :abort)
      def find_products
        log.info "Loading installed products"

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

      # ask the user about adding not installed addons to the current products
      #
      # @return [Array<Hash>] installed products and addons selected to be installed
      def merge_registered_addons
        # load the extensions to merge the registered but not installed extensions
        Addon.find_all(registration)

        # TRANSLATORS: Popup question, merge this addon that are registered but not
        # installed to the current migration products list.
        # %s is an addon friendly name, e.g 'SUSE Enterprise Storage 2 x86_64'
        msg = _("The '%s' extension is registered but not installed.\n" \
              "If you accept it will be added for be installed, in other case " \
              "it will be unregistered at the end of the migration.\n\n" \
              "Do you want to add it?")

        addons =
          Addon.registered_not_installed.each_with_object([]) do |addon, result|
            if Yast::Popup.YesNoHeadline(addon.friendly_name, (msg % addon.friendly_name))
              result << SwMgmt.remote_product(addon.to_h)
            end
          end

        products.concat(addons)
      end

      # load migration products for the installed products from the registration server,
      # loads online or offline migrations depending on the system state
      # @return [Symbol] workflow symbol (:next or :abort)
      def load_migration_products
        if Yast::Stage.initial && Yast::Mode.update
          load_migration_products_offline
        else
          load_migration_products_online
        end
      end

      # load migration products for the installed products from the registration server
      # for the currently running system (online migration)
      # @return [Symbol] workflow symbol (:next or :abort)
      def load_migration_products_online
        log.info "Loading online migration products from the server..."
        self.migrations = registration_ui.migration_products(products)

        if migrations.empty?
          # TRANSLATORS: Error message
          Yast::Report.Error(_("No migration product found."))
          return :abort
        end

        :next
      end

      # load migration products for the installed products from the registration server
      # on a system that is not running (offline migration)
      # @return [Symbol] workflow symbol (:next or :abort)
      def load_migration_products_offline
        base_product = upgraded_base_product
        if !base_product
          # TRANSLATORS: Error message
          Yast::Report.Error(_("Cannot find a base product to upgrade."))
          return :empty
        end

        remote_product = OpenStruct.new(
          arch:         base_product.arch.to_s,
          identifier:   base_product.name,
          version:      base_product.version,
          # FIXME: not supported by Y2Packager::Product yet
          release_type: nil
        )

        log.info "Loading offline migration products from the server..."
        self.migrations = registration_ui.offline_migration_products(products, remote_product)

        if migrations.empty?
          # TRANSLATORS: Error message
          Yast::Report.Error(_("No migration product found."))
          return :empty
        end

        :next
      end

      # run the migration target selection dialog
      # @return [Symbol] workflow symbol (:next or :abort)
      def select_migration_products
        log.info "Displaying migration target selection dialog"
        dialog = MigrationSelectionDialog.new(migrations, SwMgmt.installed_products)
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
          if !selected_migration.all? { |product| register_migration_product(product) }
            return :abort
          end
        ensure
          Yast::Wizard.EnableNextButton
          Yast::Wizard.EnableBackButton
        end

        # synchronize the changes done by modifying the services,
        # reinitialize the repositories
        Yast::Pkg.SourceFinishAll
        Yast::Pkg.TargetFinish
        SwMgmt.init

        # check the repositories (and possibly disable the invalid repositories)
        return :abort unless SwMgmt.check_repositories
        # reload the available packages
        Yast::Pkg.SourceLoad

        log.info "Registered services: #{registered_services}"
        :next
      ensure
        # clear the progress message
        Yast::Wizard.ClearContents
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
        ret = nil

        Yast::Popup.Feedback(RegistrationUI::CONTACTING_MESSAGE,
          # TRANSLATORS: Progress label
          _("Updating to %s ...") % product.friendly_name) do

          ret = ConnectHelpers.catch_registration_errors do
            registered_services << registration.upgrade_product(product)
          end
        end

        ret
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

      # update the $releasever
      def update_releasever
        new_base = selected_migration.find(&:base)

        if new_base
          log.info "Activating new $releasever for base product: #{new_base}"
          releasever = Releasever.new(new_base.version)
          releasever.activate
        else
          log.info "The base system is not updated, skipping $releasever update"
        end

        :next
      end

      # check the system status at upgrade and return the symbol for the next step
      # @return [Symabol] workflow symbol, :skip => do not use the SCC/SMT upgrade
      #   (unregistered system or explicitly requested by user), :next =>
      #   continue with the SCC/SMT based upgrade
      def system_upgrade_check
        # media based upgrade requested by user
        if Yast::Linuxrc.InstallInf("MediaUpgrade") == "1"
          explicit_media_upgrade
          return :skip
        # the system is registered, continue with the SCC/SMT based upgrade
        elsif Registration.is_registered?
          log.info "The system is registered, using the registration server for upgrade"
          return :next
        else
          # the system is unregistered we can only upgrade via media
          unregistered_media_upgrade
          return :skip
        end
      end

      # explicit media upgrade, requested via boot option
      def explicit_media_upgrade
        log.info "Skipping SCC upgrade, media based upgrade requested"
        if Registration.is_registered?
          Yast::Popup.LongMessageGeometry(media_upgrade(true), 60, 15)
        else
          Yast::Popup.LongMessage(media_upgrade(false))
        end
        prepare_media_upgrade
      end

      # implicit media upgrade for an unregistered system
      def unregistered_media_upgrade
        log.info "The system is NOT registered, activating the media based upgrade"
        # we do not support registering the old system at upgrade, that must
        # be done before the upgrade, skip registration in that case
        Yast::Popup.LongMessage(unregistered_message)
        prepare_media_upgrade
      end

      def prepare_media_upgrade
        # do not display the "I would like to install an additional Add On Product"
        # check box, allow adding the upgrade media directly
        Yast::SourceDialogs.display_addon_checkbox = false
        # preselect the DVD repository type
        Yast::SourceDialogs.SetURL("dvd://")
      end

      # Informative message
      # @return [String] translated message
      def unregistered_message
        # TRANSLATORS: Unregistered system message (1/3)
        #   Message displayed during upgrade for unregistered systems.
        #   The user can either boot the old system and register it or use the
        #   DVD media for upgrade. Use the RichText format.
        _("<h2>Unregistered System</h2><p>The system is not registered, that means " \
          "the installer cannot add the new software repositories required for migration " \
          "automatically.</p>") +
          # TRANSLATORS: Unregistered system message (2/3)
          _("<p>Please add the installation media manually in the next step.</p>") +
          # TRANSLATORS: Unregistered system message (3/3)
          _("<p>If you cannot provide the installation media you can abort the migration " \
          "and boot the original system to register it. Then start the migration again.</p>")
      end

      # Informative message
      # @param registered [Boolean] is the system registered?
      # @return [String] translated message
      def media_upgrade(registered)
        # TRANSLATORS: Media based upgrade requested by user (1/3)
        #   User requested media based upgrade which does not use SCC/SMT
        #   but the downloaded media (physical DVD or shared repo on a local server).
        ret = _("<h2>Media Based Upgrade</h2><p>The media based upgrade is requested. " \
          "In this mode YaST will not contact the registration server to obtain " \
          "the new software repositories required for migration.</p>") +
          # TRANSLATORS: Media based upgrade requested by user (2/3)
          _("<p>Please add the installation media manually in the next step.</p>")

        return ret unless registered

        # TRANSLATORS: a warning message, upgrading the registered systems
        #   using media is not supported
        ret + _("<h2>Warning!</h2><p><b>The media based upgrade for registered " \
          "systems is not supported!<b></p>") +
          _("<p>If you upgrade the system using media the registration status " \
            "will not be updated and the system will be still registered " \
            "using the previous product. The packages from the registration " \
            "repositories can conflict with the new packages.</p>")
      end

      def upgraded_base_product
        # temporarily run the update mode to let the solver select the product for upgrade
        # (this will correctly handle possible product renames)
        Yast::Pkg.PkgUpdateAll({})
        product = Y2Packager::Product.selected_base

        # restore the initial status, the package update will be turned on later again
        Yast::Pkg.PkgReset
        changed = Yast::Pkg.ResolvableProperties("", :package, "").select do |p|
          p["status"] != :available || p["status"] != :installed
        end
        changed.each { |p| Yast::Pkg.PkgNeutral(p["name"]) }

        log.info("Upgraded base product: #{product.inspect}")
        product
      end
    end
  end
end
