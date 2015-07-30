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
require "registration/migration_sorter"
require "registration/sw_mgmt"

module Registration
  module UI
    # this class displays and runs the dialog to select the migration target
    class MigrationSelectionDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts

      Yast.import "UI"
      Yast.import "Wizard"

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
          true,
          true
        )

        update_details

        loop do
          ret = Yast::UI.UserInput
          update_details if ret == :migration_targets
          store_values if ret == :next

          return ret if [:next, :back, :cancel, :abort].include?(ret)
        end
      end

      private

      attr_accessor :migrations

      # the main dialog content
      # @return [Yast::Term] UI term
      def dialog_content
        VBox(
          VSpacing(1),
          migration_selection_widget,

          MinHeight(8,
            VWeight(25,
              RichText(Id(:details), Opt(:vstretch), "")
            )),

          VSpacing(Yast::UI.TextMode ? 0 : 1),
          # TRANSLATORS: check button label
          CheckBox(Id(:manual_repos), _("Manually Select Migration Repositories")),
          VSpacing(1)
        )
      end

      # the main migration selection widget
      # @return [Yast::Term] UI term
      def migration_selection_widget
        MinHeight(8,
          VWeight(25,
            # TRANSLATORS: selection box label
            SelectionBox(Id(:migration_targets), Opt(:vstretch, :notify),
              _("Possible Migration Targets"), migration_items)
          ))
      end

      # list of items for the main widget
      # @return [Array<Yast::Term>] widget content
      def migration_items
        sorted_migrations.map.with_index do |arr, idx|
          products = arr.map do |product|
            "#{product.identifier}-#{product.version}"
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
      # @param [Integer] migration index
      # @return [String] user friendly description (in RichText format)
      def migration_details(idx)
        details = sorted_migrations[idx].map do |product|
          installed = installed_products.find do |installed_product|
            installed_product["name"] == product.identifier
          end

          "<li>" + product_summary(product, installed) + "</li>"
        end

        details = "<ul>" + details.join + "</ul>"
        _("<h3>Migration Summary</h3>%s") % details
      end

      def product_summary(product, installed_product)
        product_name = CGI.escapeHTML(product.friendly_name)

        if !installed_product
          # this is rather a theoretical case, but anyway....
          # TRANSLATORS: Summary message, rich text format
          # %s is a product name, e.g. "SUSE Linux Enterprise Server 12 SP1 x86_64"
          return _("%s <b>will be installed.</b>") % product_name
        end

        installed_version = installed_product["version_version"]

        if installed_version == product.version
          # TRANSLATORS: Summary message, rich text format
          # %s is a product name, e.g. "SUSE Linux Enterprise Server 12"
          return _("%s <b>stays unchanged.</b>") % product_name
        end

        old_product_name = SwMgmt.product_label(installed_product)

        # use Gem::Version for version compare
        if Gem::Version.new(installed_version) < Gem::Version.new(product.version)
          # TRANSLATORS: Summary message, rich text format
          # %{old_product} is a product name, e.g. "SUSE Linux Enterprise Server 12"
          # %{new_product} is a product name, e.g. "SUSE Linux Enterprise Server 12 SP1 x86_64"
          return _("%{old_product} <b>will be upgraded to</b> %{new_product}.") \
            % { old_product: old_product_name, new_product: product_name }
        else
          # TRANSLATORS: Summary message, rich text format
          # %{old_product} and %{new_product} are product names
          return _("%{old_product} <b>will be downgraded to</b> %{new_product}.") \
            % { old_product: old_product_name, new_product: product_name }
        end
      end

      # store the current UI values
      def store_values
        selected = Yast::UI.QueryWidget(:migration_targets, :CurrentItem)
        self.selected_migration = migrations[selected]
        log.info "Selected migration: #{selected_migration}"

        self.manual_repo_selection = Yast::UI.QueryWidget(:manual_repos, :Value)
      end

      def sorted_migrations
        # sort the products in each migration
        migrations.map do |migration|
          migration.sort(&::Registration::MIGRATION_SORTER)
        end
      end
    end
  end
end
