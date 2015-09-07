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

require "registration/repo_state"

module Registration
  module UI
    # This class handles the workflow for finishing the online migration
    class MigrationFinishWorkflow
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts

      Yast.import "Report"
      Yast.import "Sequencer"

      # run workflow for adding the migration services
      # @return [Symbol] the UI symbol
      def self.run
        workflow = MigrationFinishWorkflow.new
        workflow.run
      end

      # the constructor
      def initialize
        textdomain "registration"
      end

      # The migration finish workflow is:
      #  - restore the saved repository states (i.e. enable the Updates
      #    repositories when they were disabled during migration)
      def run
        run_sequence
      rescue => e
        log.error "Caught error: #{e.class}: #{e.message.inspect}, #{e.backtrace}"
        # TRANSLATORS: error message, %s are details
        Yast::Report.Error(_("Internal error: %s") % e.message)
        return :abort
      end

      private

      WORKFLOW_SEQUENCE = {
        "ws_start"      => "restore_repos",
        "restore_repos" => {
          abort: :abort,
          next:  :next
        }
      }

      # run the workflow
      # @return [Symbol] the UI symbol
      def run_sequence
        aliases = {
          "restore_repos" => ->() { restore_repos }
        }

        ui = Yast::Sequencer.Run(aliases, WORKFLOW_SEQUENCE)
        log.info "Workflow result: #{ui}"
        ui
      end

      # restore all saved repository states
      def restore_repos
        log.info "Restoring the original repository setup..."
        repo_state = RepoStateStorage.instance
        repo_state.read
        repo_state.restore_all
        :next
      end
    end
  end
end
