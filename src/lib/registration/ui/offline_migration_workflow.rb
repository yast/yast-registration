# ------------------------------------------------------------------------------
# Copyright (c) 2018 SUSE LLC
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
    # This class handles offline migration workflow,
    # it is a wrapper around "migration_repos" client
    class OfflineMigrationWorkflow
      include Yast::I18n
      include Yast::Logger

      Yast.import "GetInstArgs"
      Yast.import "Packages"

      # the constructor
      def initialize
        textdomain "registration"
      end

      # The offline migration workflow is:
      #
      # - run the client which adds the new migration repositories
      # - if it returns the :rollback status then run the registration rollback
      # - return the user input symbol (:next, :back or :abort) to the caller
      # @return [Symbol] the UI symbol
      #
      def main
        log.info "Starting offline migration sequence"

        if Yast::GetInstArgs.going_back
          log.info("Going back")

          if Registration.is_registered?
            log.info("Restoring the previous registration")
            rollback
          end

          return :back
        end

        # run the main registration migration
        ui = migration_repos

        rollback if ui == :rollback

        # go back in the upgrade workflow after rollback or abort,
        # maybe the user justelected a wrong partition to upgrade
        ui = :back if ui == :abort || ui == :rollback

        log.info "Offline migration result: #{ui}"
        ui
      end

    private

      def rollback
        Yast::WFM.CallFunction("registration_sync")
        # the rollback removes the initial installation repository with
        # the base product, initialize it again
        Yast::Packages.init_called = false
        Yast::Packages.Init
      end

      def migration_repos
        Yast::WFM.CallFunction("inst_migration_repos", [{ "enable_back" => true }])
      end
    end
  end
end
