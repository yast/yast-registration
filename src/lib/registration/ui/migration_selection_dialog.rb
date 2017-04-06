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

require "cgi/util"

require "yast"
require "registration/addon_sorter"
require "registration/sw_mgmt"
require "registration/url_helpers"

module Registration
  module UI
    # this class displays and runs the dialog to select the migration target
    class MigrationSelectionDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts

      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Report"
      Yast.import "HTML"
      Yast.import "GetInstArgs"

      attr_accessor :selected_migration, :manual_repo_selection, :installed_products

      # run the dialog
      # @param [Array<SUSE::Connect::Remote::Product>] migrations the available migration targets
      # @param [Array<Hash>] installed_products the currently installed products
      def self.run(migrations, installed_products)
        dialog = MigrationSelectionDialog.new(migrations, installed_products)
        dialog.run
      end

      # constructor
      # @param [Array<SUSE::Connect::Remote::Product>] migrations the available migration targets
      # @param [Array<Hash>] installed_products the currently installed products
      def initialize(migrations, installed_products)
        textdomain "registration"

        @migrations = migrations
        @installed_products = installed_products
        @manual_repo_selection = false
      end

      # display and run the dialog
      # @return [Symbol] user input
      def run
        Yast::Wizard.SetContents(
          # TRANSLATORS: dialog title
          _("Select the Migration Target"),
          dialog_content,
          # TRANSLATORS: help text (1/3)
          _("<p>Here you can select the migration target products. The registration" \
              "server may offer several possible migration to new products.</p>") +
          # TRANSLATORS: help text (2/3)
          _("<p>Only one migration target from the list can be selected.</p>") +
          # TRANSLATORS: help text (3/3), %s is replaced by the (translated) check box label
          (_("<p>Use the <b>%s</b> check box to manually select the migration " \
                "repositories later.</p>") % _("Manually Select Migration Repositories")),
          Yast::GetInstArgs.enable_back,
          true
        )

        update_details

        handle_user_input
      end

      private

      attr_accessor :migrations

      # the main loop for handling the user inut
      # @return [Symbol] the UI symbol
      def handle_user_input
        loop do
          ret = Yast::UI.UserInput

          case ret
          when :migration_targets
            update_details
          when :next
            if !current_migration
              # TRANSLATORS: error popup, no target migration is selected
              Yast::Report.Error(_("Select the target migration."))
              next
            end

            if valid_migration?
              store_values
            else
              report_unavailable_migration
              next
            end
          end

          return ret if [:next, :back, :cancel, :abort].include?(ret)
        end
      end

      # is the current selected migration valid? (a migration is selected and
      # all products are available)
      # @return [Boolean] true if the migration can be used
      def valid_migration?
        # available is nil (not set) or true
        current_migration.all? { |p| p.available.nil? || p.available }
      end

      def add_registered_addons
        extra = Addon.registered_not_installed.map { |addon| SwMgmt.remote_product(addon) }
        installed_products.concat(extra)
      end

      # the main dialog content
      # @return [Yast::Term] UI term
      def dialog_content
        VBox(
          VSpacing(1),
          migration_selection_widget,
          VWeight(15,
            RichText(Id(:details), Opt(:vstretch), "")
          ),

          VSpacing(Yast::UI.TextMode ? 0 : 1),
          # TRANSLATORS: check button label
          CheckBox(Id(:manual_repos), _("Manually Adjust the Repositories for Migration")),
          VSpacing(Yast::UI.TextMode ? 0 : 1)
        )
      end

      # the main migration selection widget
      # @return [Yast::Term] UI term
      def migration_selection_widget
        # make the selection widget size depending on the number of available migrations
        # (limit the size to have reasonable space for the details below)
        weight = [5 + migrations.size, 10].min

        VWeight(weight,
          # TRANSLATORS: selection box label
          SelectionBox(Id(:migration_targets), Opt(:vstretch, :notify),
            _("Possible Migration Targets"), migration_items)
        )
      end

      # list of items for the main widget
      # @return [Array<Yast::Term>] widget content
      def migration_items
        sorted_migrations.map.with_index do |arr, idx|
          products = arr.map do |product|
            product.shortname || "#{product.identifier}-#{product.version}"
          end

          Item(Id(idx), products.join(", "))
        end
      end

      # update details about the selected migration
      def update_details
        log.info "updating details"
        selected = Yast::UI.QueryWidget(:migration_targets, :CurrentItem)
        return unless selected

        Yast::UI.ChangeWidget(Id(:details), :Value, migration_details(selected))
      end

      # get migration details
      # @param [Integer] idx migration index
      # @return [String] user friendly description (in RichText format)
      def migration_details(idx)
        products_to_migrate = []

        details = sorted_migrations[idx].map do |product|
          installed = installed_products.find do |installed_product|
            installed_product["name"] == product.identifier
          end

          products_to_migrate << installed if installed

          "<li>" + product_summary(product, installed) + "</li>"
        end

        installed_products.each do |installed_product|
          next if products_to_migrate.include?(installed_product)

          details << "<li>" + product_summary(nil, installed_product) + "</li>"
        end

        # TRANSLATORS: RichText header (details for the selected item)
        "<h3>" + _("Migration Summary") + "</h3><ul>" + details.join + "</ul>"
      end

      # create a product summary for the details widget
      # @return [String] product summary
      def product_summary(product, installed_product)
        log.info "creating summary for #{product} and #{installed_product}"

        if !product
          product_name = CGI.escapeHTML(SwMgmt.product_label(installed_product))
          # TRANSLATORS: Summary message in rich text format
          # %s is a product name, e.g. "SUSE Linux Enterprise Server 12 SP1 x86_64"
          return _("The registration server does not offer migrations for Product " \
                   "<b>%s</b> so it will <b>stay unchanged</b>. We recommend you " \
                   "to check if it's correct and to configure the repositories " \
                   "manually in case of needed.") % product_name

        end

        product_name = CGI.escapeHTML(product.friendly_name)

        # explicitly check for false, the flag is not returned by SCC, this is
        # a SMT specific check (in SCC all products are implicitly available)
        if product.available == false
          # a product can be unavailable only when using SMT, the default
          # SCC URL should be never used
          url = UrlHelpers.registration_url || SUSE::Connect::YaST::DEFAULT_URL

          # TRANSLATORS: An error message displayed in the migration details.
          # The product has not been mirrored to the SMT server and cannot be used
          # for migration. The SMT admin has to mirror the product to allow
          # using the selected migration.
          # %{url} is the URL of the registration server (SMT)
          # %{product} is a full product name, e.g. "SUSE Linux Enterprise Server 12"
          return Yast::HTML.Colorize(
            _("ERROR: Product <b>%{product}</b> is not available at the " \
                "registration server (%{url}). Make the product available " \
                "to allow using this migration.") %
            { product: product_name, url: url },
            "red")
        end

        if !installed_product
          # this is rather a theoretical case, but anyway....
          # TRANSLATORS: Summary message, rich text format
          # %s is a product name, e.g. "SUSE Linux Enterprise Server 12 SP1 x86_64"
          return _("%s <b>will be installed.</b>") % product_name
        end

        product_change_summary(installed_product, product)
      end

      # create a summary for changed product
      # @param [Hash] old_product the old installed libzypp product
      # @param [OpenStruct] new_product the new target product
      # @return [String] RichText summary
      def product_change_summary(old_product, new_product)
        new_product_name = CGI.escapeHTML(new_product.friendly_name)
        installed_version = old_product["version_version"]

        if installed_version == new_product.version
          # TRANSLATORS: Summary message, rich text format
          # %s is a product name, e.g. "SUSE Linux Enterprise Server 12"
          return _("%s <b>stays unchanged.</b>") % new_product_name
        end

        old_product_name = SwMgmt.product_label(old_product)

        # use Gem::Version for version compare
        if Gem::Version.new(installed_version) < Gem::Version.new(new_product.version)
          # TRANSLATORS: Summary message, rich text format
          # %{old_product} is a product name, e.g. "SUSE Linux Enterprise Server 12"
          # %{new_product} is a product name, e.g. "SUSE Linux Enterprise Server 12 SP1 x86_64"
          return _("%{old_product} <b>will be upgraded to</b> %{new_product}.") \
            % { old_product: old_product_name, new_product: new_product_name }
        else
          # TRANSLATORS: Summary message, rich text format
          # %{old_product} and %{new_product} are product names
          return _("%{old_product} <b>will be downgraded to</b> %{new_product}.") \
            % { old_product: old_product_name, new_product: new_product_name }
        end
      end

      # store the current UI values
      def store_values
        self.selected_migration = current_migration
        self.manual_repo_selection = Yast::UI.QueryWidget(:manual_repos, :Value)
      end

      # return the currently selected migration
      # @return [Array<OpenStruct>] the selected migration target
      def current_migration
        current_item = Yast::UI.QueryWidget(:migration_targets, :CurrentItem)
        migration = migrations[current_item]
        log.info "Selected migration: #{migration}"
        migration
      end

      def sorted_migrations
        # sort the products in each migration
        migrations.map do |migration|
          # use the addon sorter, put the base product(s) at the end
          base = migration.select { |m| m.product_type == "base" }
          addons = migration - base
          addons.sort(&::Registration::ADDON_SORTER) + base
        end
      end

      # display an error popup
      def report_unavailable_migration
        # TRANSLATORS: an error popup message
        Yast::Report.Error(_("The selected migration contains a product\n" \
              "which is not available at the registration server.\n\n" \
              "Select a different migration target or make the missing products\n" \
              "available at the registration server."))
      end
    end
  end
end
