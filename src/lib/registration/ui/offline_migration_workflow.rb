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
      Yast.import "Installation"
      Yast.import "Wizard"
      Yast.import "Pkg"

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

        # display an empty dialog just to hide the content of the previous step
        Yast::Wizard.ClearContents

        if Yast::GetInstArgs.going_back
          log.info("Going back")

          if Registration.is_registered?
            log.info("Restoring the previous registration")
            rollback
            restore_installation_repos
          end

          return :back
        else
          backup_installation_repos
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

        if Yast::Stage.initial && File.exist?(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
          log.info("Removing #{SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE}...")
          File.delete(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        end
      end

      def migration_repos
        Yast::WFM.CallFunction("inst_migration_repos", [{ "enable_back" => true }])
      end

      def backup_installation_repos
        ids = Yast::Pkg.SourceGetCurrent(false)
        @@repos_backup = ids.map { |r| Yast::Pkg.SourceGeneralData(r) }
      end

      def restore_installation_repos
        return unless @@repos_backup
        Yast::Pkg.SourceFinishAll
        Yast::Pkg.TargetFinish
        Yast::Pkg.TargetInitialize("/")

        @@repos_backup.each { |r| Yast::Pkg.RepositoryAdd(r) }

        Yast::Pkg.SourceLoad
        Yast::Pkg.TargetFinish
        Yast::Pkg.TargetInitialize(Yast::Installation.destdir)
      end
    end
  end
end
