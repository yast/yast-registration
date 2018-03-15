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
require "uri"

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
      Yast.import "AddOnProduct"

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
          end

          return :back
        end

        # run the main registration migration
        ui = migration_repos

        rollback if ui == :rollback

        # refresh the add-on records
        update_addon_records

        # go back in the upgrade workflow after rollback or abort,
        # maybe the user justelected a wrong partition to upgrade
        ui = :back if ui == :abort || ui == :rollback

        log.info "Offline migration result: #{ui}"
        ui
      end

    private

      def rollback
        Yast::WFM.CallFunction("registration_sync")

        # remove the copied credentials file from the target system to not be
        # used again by mistake (skip if accidentally called in a running system)
        if Yast::Stage.initial && File.exist?(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
          log.info("Removing #{SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE}...")
          File.delete(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        end
      end

      def migration_repos
        Yast::WFM.CallFunction("inst_migration_repos", [{ "enable_back" => true }])
      end

      # update the repository IDs in the AddOnProduct records
      def update_addon_records
        Yast::AddOnProduct.add_on_products.each do |addon|
          next unless addon["media_url"]

          url = URI(addon["media_url"])
          dir = addon["product_dir"]
          log.info("Refreshing repository ID for addon #{addon["product"]} (#{url})")

          # remove the alias from the URL if it is preset, it is removed by Pkg bindings
          # when adding the repository so it would not match
          if url.query
            # params is a list of pairs, "foo=bar" => [["foo, "bar]]
            params = URI.decode_www_form(url.query)
            params.reject! { |p| p.first == "alias" }
            # avoid empty query after "?" in URL
            url.query = params.empty? ? nil : URI.encode_www_form(params)
          end

          new_id = Yast::Pkg.SourceGetCurrent(false).find do |repo|
            data = Yast::Pkg.SourceGeneralData(repo)
            # the same URL and product dir
            URI(data["url"]) == url && data["product_dir"] == dir
          end

          if new_id
            log.info("Updating ID: #{addon["media"]} -> #{new_id}")
            addon["media"] = new_id
          else
            log.warn("Addon not found")
          end
        end
      end
    end
  end
end
