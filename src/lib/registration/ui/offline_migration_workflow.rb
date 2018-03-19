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
          going_back
          return :back
        end

        # run the main registration migration
        ui = migration_repos

        rollback if ui == :rollback

        if [:back, :abort, :rollback].include?(ui)
          inst_sys_cleanup
          # go back in the upgrade workflow after rollback or abort,
          # maybe the user just selected a wrong partition to upgrade
          ui = :back
        else
          # refresh the add-on records
          update_addon_records
        end

        log.info "Offline migration result: #{ui}"
        ui
      end

    private

      def going_back
        log.info("Going back")

        if Registration.is_registered?
          log.info("Restoring the previous registration")
          rollback
        end

        inst_sys_cleanup
      end

      def rollback
        Yast::WFM.CallFunction("registration_sync")
      end

      # cleanup the inst-sys, remove the files copied from the target system
      def inst_sys_cleanup
        # skip inst-sys cleanup if accidentally called in a running system
        return unless Yast::Stage.initial

        # remove the copied credentials file from the inst-sys
        if File.exist?(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
          log.info("Removing #{SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE}...")
          File.delete(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
        end

        # remove the SSL certificate from the inst-sys
        if File.exist?(SslCertificate::INSTSYS_SERVER_CERT_FILE)
          log.info("Removing the imported SSL certificate from the inst-sys...")
          File.delete(SslCertificate::INSTSYS_SERVER_CERT_FILE)
          # FIXME: this does not remove the already imported certificate from
          # /var/lib/ca-certificates
          SslCertificate.update_instsys_ca
        end
      end

      def migration_repos
        Yast::WFM.CallFunction("inst_migration_repos", [{ "enable_back" => true }])
      end

      # update the repository IDs in the AddOnProduct records, the migration
      # updates the repository setup and the source IDs might not match anymore
      def update_addon_records
        Yast::AddOnProduct.add_on_products.each do |addon|
          next unless addon["media_url"]

          url = URI(addon["media_url"])
          log.info("Refreshing repository ID for addon #{addon["product"]} (#{url})")

          # remove the alias from the URL if it is preset, it is removed by Pkg bindings
          # when adding the repository so it would not match
          remove_alias(url)

          update_addon(addon, url)
        end
      end

      # remove the "alias" query URL parameter from the URL if it is present
      # @param url [URI] input URL
      def remove_alias(url)
        if url.query
          # params is a list of pairs, "foo=bar" => [["foo, "bar]]
          params = URI.decode_www_form(url.query)
          params.reject! { |p| p.first == "alias" }
          # avoid empty query after "?" in URL
          url.query = params.empty? ? nil : URI.encode_www_form(params)
        end
      end

      # Find the repository ID for the URL and product dir
      # @param url [URI] repository URL
      # @param dir [String] product directory
      # @return [Integer,nil] repository ID
      def find_repo_id(url, dir)
        Yast::Pkg.SourceGetCurrent(false).find do |repo|
          data = Yast::Pkg.SourceGeneralData(repo)
          # the same URL and product dir
          URI(data["url"]) == url && data["product_dir"] == dir
        end
      end

      # update an addon record
      # @param addon [Hash] an addon record
      # @param url [URI] URL of the addon (without "alias")
      def update_addon(addon, url)
        new_id = find_repo_id(url, addon["product_dir"])

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
