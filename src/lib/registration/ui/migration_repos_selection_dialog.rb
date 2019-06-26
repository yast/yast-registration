# typed: false
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
          _("Repositories used for Migration"),
          dialog_content,
          # TRANSLATORS: help text
          _("<p>In this dialog you can manually select which repositories will" \
              "be used for online migration. The packages will be upgraded to the" \
              "highest version found in the selected repositories.</p>"),
          true,
          true
        )

        update_repo_details

        loop do
          ret = Yast::UI.UserInput

          case ret
          when :next
            store_values
          when :repo_mgmt
            repo_mgmt
          when :repos
            update_repo_details
          end

          return ret if [:next, :back, :cancel, :abort].include?(ret)
        end
      end

    private

      attr_accessor :migrations

      # the main dialog content
      # @return [Yast::Term] UI term
      def dialog_content
        VBox(
          VWeight(75, MultiSelectionBox(Id(:repos), Opt(:vstretch, :notify),
            # TRANSLATORS: Multiselection widget label
            _("Select the Repositories used for Migration"), repo_items)),
          MinHeight(6, VWeight(25, RichText(Id(:details), ""))),
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
          repo_props = Yast::Pkg.SourceGeneralData(repo)
          Item(Id(repo), repo_props["name"], repo_props["enabled"])
        end
      end

      def repo_details(repo)
        # TRANSLATORS: summary text, %s is a repository URL
        url_label = _("URL: %s") % repo["url"]
        # TRANSLATORS: summary text, %s is a repository priority (1-99)
        priority_label = _("Priority: %s") % repo["priority"]

        "<p><b><big>#{repo["name"]}</big></b></p><p>#{url_label}<br>#{priority_label}</p>"
      end

      def update_repo_details
        log.debug "Currently selected item: #{Yast::UI.QueryWidget(:repos, :CurrentItem)}"
        current = Yast::UI.QueryWidget(:repos, :CurrentItem)

        return unless current

        Yast::UI.ChangeWidget(Id(:details), :Value,
          repo_details(Yast::Pkg.SourceGeneralData(current)))
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
        store_values
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
