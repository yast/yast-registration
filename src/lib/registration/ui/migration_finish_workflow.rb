# typed: true
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

require "registration/repo_state"
require "registration/ui/wizard_client"

module Registration
  module UI
    # This class handles the workflow for finishing the online migration
    class MigrationFinishWorkflow < WizardClient
      # Run the workflow.
      # The migration finish workflow is:
      #  - restore the saved repository states (i.e. enable the Updates
      #    repositories when they were disabled during migration)
      # @return [Symbol] the UI symbol
      def run_sequence
        log.info "Restoring the original repository setup..."
        repo_state = RepoStateStorage.instance
        repo_state.read
        repo_state.restore_all
        :next
      end
    end
  end
end
