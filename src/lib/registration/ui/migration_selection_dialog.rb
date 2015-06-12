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

module Registration
  module UI
    # this class displays and runs the dialog to select the migration target
    class MigrationSelectionDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts

      Yast.import "UI"
      Yast.import "Wizard"

      attr_accessor :selected_migration, :manual_repo_selection

      # run the dialog
      # @param [Array<SUSE::Connect::Remote::Product>] the available migration targets
      def self.run(migrations)
        dialog = MigrationSelectionDialog.new(migrations)
        dialog.run
      end

      # constructor
      # @param [Array<SUSE::Connect::Remote::Product>] the available migration targets
      def initialize(migrations)
        textdomain "registration"

        @migrations = migrations
        @manual_repo_selection = false
      end

      # display and run the dialog
      # @return [Symbol] user input
      def run
        Yast::Wizard.SetContents(
          # TRANSLATORS: dialog title
          _("Select the Migration Target"),
          dialog_content,
          # TRANSLATORS: help text
          # FIXME: help text
          _("FIXME"),
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
          CheckBox(Id(:manual_repos), _("Manually Select Migration Repositoreis")),
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
        migrations.map.with_index do |arr, idx|
          products = arr.map do |product|
            "#{product.identifier}-#{product.version}-#{product.arch}"
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
        # TODO: display some more user friendly details
        details = migrations[idx].map do |product|
          "<li>" + CGI.escapeHTML("#{product.identifier}-#{product.version}-#{product.arch}") +
            "</li>"
        end

        details = "<ul>" + details.join + "</ul>"
        _("<h3>Migration Products Details</h3>%s") % details
      end

      # store the current UI values
      def store_values
        selected = Yast::UI.QueryWidget(:migration_targets, :CurrentItem)
        self.selected_migration = migrations[selected]
        log.info "Selected migration: #{selected_migration}"

        self.manual_repo_selection = Yast::UI.QueryWidget(:manual_repos, :Value)
      end
    end
  end
end
