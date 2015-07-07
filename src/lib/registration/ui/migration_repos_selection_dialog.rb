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

module Registration
  module UI
    # dialog for manual migration repository selection
    class MigrationReposSelectionDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts

      Yast.import "Pkg"
      Yast.import "Wizard"

      attr_accessor :selected_migration, :manual_repo_selection

      # display and run the dialog
      # @return [Symbol] user input
      def self.run
        dialog = MigrationReposSelectionDialog.new
        dialog.run
      end

      # constructor
      def initialize
        textdomain "registration"
      end

      # display and run the dialog
      # @return [Symbol] user input
      def run
        Yast::Wizard.SetContents(
          # TRANSLATORS: dialog title
          _("Migration Repositories"),
          dialog_content,
          # TRANSLATORS: help text
          _("<p>In this dialog you can manually select which repositories will" \
            "be used for online migration. The packages will be upgraded to the" \
            "highest version found in the selected repositories.</p>"),
          true,
          true
        )

        loop do
          ret = Yast::UI.UserInput

          store_values if ret == :next
          repo_mgmt if ret == :repo_mgmt

          return ret if [:next, :back, :cancel, :abort].include?(ret)
        end
      end

      private

      attr_accessor :migrations

      # the main dialog content
      # @return [Yast::Term] UI term
      def dialog_content
        VBox(
          MultiSelectionBox(Id(:repos), Opt(:vstretch),
            _("Select the Migration Repositories"), repo_items
          ),
          # TRANSLATORS: Push button label, starts the repository management module
          PushButton(Id(:repo_mgmt), _("Manage Repositories..."))
        )
      end

      # list of repository items
      # @return [Array<Yast::Term>] content for a MultiSelectionBox widget
      def repo_items
        # all repositories
        repos = Yast::Pkg.SourceGetCurrent(false)

        # sort the repositories by name
        repos.sort! do |x, y|
          # locale dependent sorting
          Yast.strcoll(Yast::Pkg.SourceGeneralData(x)["name"],
            Yast::Pkg.SourceGeneralData(y)["name"])
        end

        repos.map do |repo|
          Item(Id(repo), repo_label(repo), Yast::Pkg.SourceGeneralData(repo)["enabled"])
        end
      end

      # repository label, displayed in the MultiSelectionBox widget
      # @param [Hash] repository data
      # @return [String] label
      def repo_label(repo)
        repo_data = Yast::Pkg.SourceGeneralData(repo)
        "#{repo_data["name"]} (#{repo_data["url"]})"
      end

      # activate the selection in the dialog
      def store_values
        selected = Yast::UI.QueryWidget(:repos, :SelectedItems)
        log.info "Selected migration repositories: #{selected}"

        # reset the current settings
        MigrationRepositories.reset

        # activate the new settings
        migration_repos = MigrationRepositories.new
        migration_repos.repositories = selected
        migration_repos.activate_repositories
      end

      # run the repository management, refresh the dialog content if it
      # has not been aborted
      def repo_mgmt
        # refresh enabled repositories so they are up-to-date
        ret = Yast::WFM.call("repositories", ["refresh-enabled"])
        return :abort if ret == :abort

        # refresh the dialog content
        Yast::UI.ChangeWidget(:repos, :Items, repo_items)

        ret
      end
    end
  end
end
