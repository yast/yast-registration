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

require "registration/registration"
require "registration/registration_ui"
require "registration/releasever"
require "registration/sw_mgmt"
require "registration/storage"
require "registration/url_helpers"
require "registration/ui/wizard_client"

module Registration
  module UI
    # This class handles synchronizing the repositories/services after abort
    class RegistrationSyncWorkflow < WizardClient
      include Yast::UIShortcuts

      Yast.import "Pkg"
      Yast.import "Update"
      Yast.import "Installation"

      # the constructor
      def initialize
        textdomain "registration"

        self.registration = Registration.new(UrlHelpers.registration_url)
        self.registration_ui = RegistrationUI.new(registration)
      end

      # workaround for rollback from the Leap => SLES migration,
      # maps installed => activated product
      SYNC_FALLBACKS = {
        "openSUSE" => "SLES",
        # openSUSE Leap 15.3 and newer
        "Leap"     => "SLES"
      }.freeze

      # restore the registration status
      # @return [Symbol] :next on success, :abort on error
      def run_sequence
        log.info "Restoring the original repository and registration status..."

        restore_repos

        # load the installed products that are activated
        Yast::Pkg.TargetLoad
        activated = registration.activated_products.map(&:identifier)
        products =
          SwMgmt.installed_products.each_with_object([]) do |product, result|
            name = product["name"]
            next unless activated.include?(name) || activated.include?(SYNC_FALLBACKS[name])
            result << product
          end

        # Ask the user about adding all the registered but not installed addons
        # to the rollback
        addons = registration_ui.registered_addons_to_rollback
        log.info "Addons registered but not installed: #{addons}"

        products.concat(addons)

        # downgrade all installed products
        return :abort unless downgrade_products(products)
        remove_rollback_script

        reload_repos

        # synchronize the products (remove additional registrations at the server)
        registration_ui.synchronize_products(products) ? :next : :abort
      end

    private

      attr_accessor :registration_ui, :registration

      # restore the repositories from the backup archive
      def restore_repos
        # finish the sources and the target to reload the repositories from the backup
        Yast::Pkg.SourceFinishAll
        Yast::Pkg.TargetFinish
        Yast::Update.restore_backup
        Yast::Pkg.TargetInitialize(Yast::Installation.destdir)
      end

      # reload the repositories to synchronize the changes, reset the $releasever value
      # if it has been set and refresh the affected repositories
      def reload_repos
        Yast::Pkg.SourceFinishAll
        Yast::Pkg.SourceRestore

        return unless Releasever.set?

        log.info "Resetting the $releasever..."
        releasever = Releasever.new(nil)
        releasever.activate
      end

      # downgrade product registrations (restore the original status before upgrading)
      # @return [Boolean] true on success
      def downgrade_products(products)
        # sort the products so the base product is downgraded first
        sorted_products = products.sort_by { |p| p["category"] == "base" ? 0 : 1 }
        sorted_products.all? do |product|
          product["release_type"] = SwMgmt.get_release_type(product)
          success, _service = registration_ui.downgrade_product(product)
          success
        end
      end

      # remove the rollback script after doing the rollback by YaST
      # (avoid double rollback)
      def remove_rollback_script
        rollback = Storage::Cache.instance.rollback
        return unless rollback

        # remove the saved script and drop the cache
        rollback.delete
        Storage::Cache.instance.rollback = nil
      end
    end
  end
end
