# ***************************************************************************
#
# Copyright (c) 2019 SUSE LLC
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail,
# you may find current contact information at www.novell.com
#
# ***************************************************************************

require "fileutils"
require "yast/suse_connect"

require "installation/auto_client"
require "registration/storage"
require "registration/sw_mgmt"
require "registration/autoyast_addons"
require "registration/registration"
require "registration/registration_ui"
require "registration/helpers"
require "registration/connect_helpers"
require "registration/ssl_certificate"
require "registration/url_helpers"
require "registration/ui/autoyast_config_workflow"
require "registration/ui/offline_migration_workflow"
require "registration/erb_renderer"
require "y2packager/product_spec"
require "y2packager/medium_type"

Yast.import "UI"
Yast.import "Pkg"
Yast.import "Wizard"
Yast.import "Label"
Yast.import "Report"
Yast.import "Popup"
Yast.import "Packages"
Yast.import "Report"
Yast.import "Installation"

module Registration
  module Clients
    class SCCAuto < ::Installation::AutoClient
      include Yast::Logger
      extend Yast::I18n

      # popup message
      CONTACTING_MESSAGE = N_("Contacting the Registration Server")

      def initialize
        super
        textdomain "registration"

        @config = ::Registration::Storage::Config.instance
      end

      # Create a textual summary
      # @return [String] summary of the current configuration
      def summary
        ::Registration::ErbRenderer.new(@config).render_erb_template("autoyast_summary.erb")
      end

      def reset
        @config.reset
        {}
      end

      # UI workflow definition
      def change
        ::Registration::UI::AutoyastConfigWorkflow.run(@config)
      end

      # Get all settings from the first parameter
      # (For use by autoinstallation.)
      # param [Hash] settings The structure to be imported.
      def import(settings)
        # if there is no registration section like can happen during auto upgrade
        return unless settings

        # Lazy load it as registration does not depend on ay, but scc_auto is run only in ay context
        Yast.import "AutoinstFunctions"

        # merge reg code if not defined in the profile but
        # available from other sources
        product = Yast::AutoinstFunctions.selected_product
        # If the real product (an instance from the Product class) is not
        # available (e.g. Online medium), just skip reading the regcode because
        # the short_name (which is required to find the regcode) is unknown at
        # this point. See bsc#1194440.
        if product.respond_to?(:short_name) && !settings["reg_code"]
          reg_codes_loader = ::Registration::Storage::RegCodes.instance
          settings["reg_code"] = reg_codes_loader.reg_codes[product.short_name] || ""
        end

        log.debug "Importing config: #{settings}"
        @config.import(settings)
      end

      # Export the settings to a single Hash
      # (For use by autoinstallation.)
      # @return [Hash] AutoYast configuration
      def export
        ret = @config.export
        log.debug "Exported config: #{ret}"
        ret
      end

      # register the system, base product and optional addons
      # return true on success
      def write
        # registration disabled, nothing to do
        return true if !@config.do_registration && !Yast::Mode.update

        # initialize libzypp if applying settings in installed system or
        # in AutoYast configuration mode ("Apply to System")
        ::Registration::SwMgmt.init if Yast::Mode.normal || Yast::Mode.config

        return false unless set_registration_url

        # update the registration in AutoUpgrade mode if the old system was registered
        return migrate_reg if Yast::Mode.update

        # special handling for the online installation medium,
        # we need to evaluate the base products defined in the control.xml
        if Yast::Stage.initial && Y2Packager::MediumType.online? && !online_medium_config
          return false
        end

        ret = ::Registration::ConnectHelpers.catch_registration_errors do
          import_certificate(@config.reg_server_cert)
          register_base_product && register_addons
        end

        return false unless ret

        finish_registration

        true
      end

      def read
        ::Registration::ConnectHelpers.catch_registration_errors do
          @config.read
        end
      end

      # return extra packages needed by this module (none so far)
      # @return [Hash] required packages
      def packages
        ret = { "install" => [], "remove" => [] }
        log.info "Registration needs these packages: #{ret}"
        ret
      end

      def modified?
        @config.modified
      end

      def modified
        @config.modified = true
        true
      end

    private

      # set the registration URL from the profile or use the default
      # @return [Boolean] true on success
      def set_registration_url
        # set the registration URL
        url = @config.reg_server if @config.reg_server && !@config.reg_server.empty?

        # use SLP discovery
        if !url && @config.slp_discovery
          url = find_slp_server
          return false unless url
        end

        url ||= ::Registration::UrlHelpers.registration_url
        log.info "Registration URL: #{url}"

        # nil = use the default URL
        switch_registration(url)

        true
      end

      # Select the product from the control.xml (for the online installation medium)
      # @return [Boolean] true on success, false on failure
      def online_medium_config
        # import the GPG keys before refreshing the repositories
        Yast::Packages.ImportGPGKeys

        products = Y2Packager::ProductSpec.base_products

        # Lazy load it as registration does not depend on ay, but scc_auto is run only in ay context
        Yast.import "AutoinstFunctions"

        selected_product = Yast::AutoinstFunctions.selected_product
        log.info "selected product #{selected_product.inspect}"

        if !selected_product
          # TRANSLATORS: error message, %s is the XML path, e.g. "software/products"
          Yast::Report.Error(
            _("Missing product specification in the %s section") % "software/products"
          )
          return false
        end

        ay_product = selected_product.name
        control_product = products.find { |p| p.name == ay_product }

        if !control_product
          # TRANSLATORS: error message, %s is a product ID, e.g. "SLES"
          Yast::Report.Error(_("Product %s not found") % ay_product)
          return false
        end

        # mark the control file product as selected
        control_product.select

        true
      end

      # delete all previous services and repositories
      def repo_cleanup
        # we cannot use pkg-bindings here because loading services would trigger
        # service and repository refresh which we want to avoid (it might easily fail)
        old = Dir[File.join(Installation.destdir, "/etc/zypp/repos.d/*")] +
          Dir[File.join(Installation.destdir, "/etc/zypp/services.d/*")] +
          Dir[File.join(Installation.destdir, "/var/cache/zypp/*")]

        log.info "Removing #{old}"
        ::FileUtils.rm_rf(old)
      end

      # finish the registration process
      def finish_registration
        # save the registered repositories
        Yast::Pkg.SourceSaveAll

        if Yast::Mode.normal || Yast::Mode.config
          # popup message: registration finished properly
          Yast::Popup.Message(_("Registration was successfull."))
        elsif Yast::Stage.initial
          # copy the SSL certificate to the target system
          ::Registration::Helpers.copy_certificate_to_target
        end
      end

      # find registration server via SLP
      # @return [String,nil] URL of the server, nil on error
      def find_slp_server
        # do SLP query
        slp_services = ::Registration::UrlHelpers.slp_discovery_feedback
        slp_urls = slp_services.map(&:slp_url)

        # remove possible duplicates
        slp_urls.uniq!
        log.info "Found #{slp_urls.size} SLP servers"

        case slp_urls.size
        when 0
          Yast::Report.Error(_("SLP discovery failed, no server found"))
          nil
        when 1
          slp_urls.first
        else
          # more than one server found: let the user select, we cannot automatically
          # decide which one to use, asking user in AutoYast mode is not nice
          # but better than aborting the installation...
          ::Registration::UrlHelpers.slp_service_url
        end
      end

      # download and install the specified SSL certificate to the system
      # @param url [String] URL of the certificate
      def import_certificate(url)
        return unless url && !url.empty?

        log.info "Importing certificate from #{url}..."

        cert = Yast::Popup.Feedback(_("Downloading SSL Certificate"), url) do
          ::Registration::SslCertificate.download(url)
        end

        Yast::Popup.Feedback(_("Importing SSL Certificate"), cert.subject_name) do
          cert.import
        end
      end

      # update the internal Registration object after changing the registration URL
      def switch_registration(url = nil)
        @registration = ::Registration::Registration.new(url)
        # reset registration ui as it depends on registration
        @registration_ui = nil
        @registration
      end

      # returns the internal Registration object
      def registration
        if !@registration
          url = ::Registration::UrlHelpers.registration_url
          log.info "Updating registration using URL: #{url}"
          @registration = switch_registration(url)
        end

        @registration
      end

      # returns the internal RegistrationUI object
      def registration_ui
        @registration_ui ||= ::Registration::RegistrationUI.new(registration)
      end

      # update the registration (system, the base product, the installed extensions)
      def update_registration
        return false unless update_system_registration

        # register additional addons (e.g. originally not present in SLE11/SLE12)
        register_addons
      end

      # FIXME: share these methods with inst_scc.rb

      def register_base_product
        handle_product_service do
          options = ::Registration::Storage::InstallationOptions.instance
          options.email = @config.email
          options.reg_code = @config.reg_code

          registration_ui.register_system_and_base_product
        end
      end

      # register the addons specified in the profile
      def register_addons
        # set the option for installing the updates for addons
        options = ::Registration::Storage::InstallationOptions.instance
        options.install_updates = @config.install_updates

        ay_addons_handler = ::Registration::AutoyastAddons.new(@config.addons, registration)
        ay_addons_handler.select
        ay_addons_handler.register

        # select the new products to install
        ::Registration::SwMgmt.select_addon_products
      end

      # was the system already registered?
      # @return [Boolean] true if the system was alreay registered
      def old_system_registered?
        ::Registration::SwMgmt.copy_old_credentials(Yast::Installation.destdir)

        # update the registration using the old credentials
        ::File.exist?(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
      end

      # update the system registration
      # @return [Boolean] true on success
      def update_system_registration
        registration_ui.update_system
      end

      # @yieldreturn [Boolean, SUSE::Connect::Remote::Product] success flag and
      #   remote product pair
      # @return [Boolean] true on success
      def handle_product_service(&block)
        success, product_service = block.call
        return false unless success

        # keep updates enabled?
        return true if @config.install_updates || !product_service

        registration_ui.disable_update_repos(product_service)
      end

      # migrate registration if applicable or skip or report issue.
      def migrate_reg
        if old_system_registered?
          # act always like we have online only repo for registered system
          Y2Packager::MediumType.type = :online

          # drop all obsolete repositories and services (manual upgrade contains a dialog
          # where the old repositories are deleted, in AY we need to do it automatically here)
          # Note: the Update module creates automatically a backup which is restored
          # when upgrade is aborted or crashes.
          repo_cleanup

          ret = ::Registration::UI::OfflineMigrationWorkflow.new.main
          log.info "Migration result: #{ret}"
          ret == :next
        # Full medium we can upgrade without registration
        elsif Y2Packager::MediumType.offline?
          true
        else
          # Intentionally use blocking popup as it is fatal error that stops installation.
          Yast::Popup.Error(
            # TRANSLATORS: profile wants to do registration, but old system is not registered.
            _("The old system is not registered and the AutoYaST profile requires registration.\n" \
              "Either register the old system before running the upgrade or \n" \
              "remove the registration section from the AutoYaST profile \n" \
              "and use full medium.")
          )
          false
        end
      end
    end
  end
end
