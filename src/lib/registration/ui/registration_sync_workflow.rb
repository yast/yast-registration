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

        registration = Registration.new(UrlHelpers.registration_url)
        self.registration_ui = RegistrationUI.new(registration)
      end

      # restore the registration status
      # @return [Symbol] :next on sucess, :abort on error
      def run_sequence
        log.info "Restoring the original repository and registration status..."

        restore_repos

        # load the installed products
        Yast::Pkg.TargetLoad
        products = SwMgmt.installed_products

        # downgrade all installed products
        return :abort unless downgrade_products(products)

        reload_repos

        # synchronize all installed products (remove additional registrations at the server)
        registration_ui.synchronize_products(products) ? :next : :abort
      end

    private

      attr_accessor :registration_ui

      # restore the repositpories from the backup archive
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
    end
  end
end
