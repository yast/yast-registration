# encoding: utf-8

# ***************************************************************************
#
# Copyright (c) 2014 SUSE LLC
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
#
# Summary: Configure Product Registration for Autoinstallation
#
#

require "yast/suse_connect"
require "erb"

require "registration/storage"
require "registration/sw_mgmt"
require "registration/registration"
require "registration/registration_ui"
require "registration/helpers"
require "registration/connect_helpers"
require "registration/ssl_certificate"
require "registration/url_helpers"
require "registration/ui/autoyast_config_workflow"

module Yast
  class SccAutoClient < Client
    include Yast::Logger
    include ERB::Util
    extend Yast::I18n

    # popup message
    CONTACTING_MESSAGE = N_("Contacting the Registration Server")

    def main
      textdomain "registration"
      import_modules

      log.info "scc_auto started"

      @config = ::Registration::Storage::Config.instance
      func = WFM.Args[0]
      param = WFM.Args[1] || {}
      log.info "func: #{func}, param: #{::Registration::Helpers.hide_reg_codes(param)}"

      ret = handle_autoyast(func, param)

      log.info "scc_auto finished"
      ret
    end

  private

    def import_modules
      Yast.import "UI"
      Yast.import "Pkg"
      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Report"
      Yast.import "Popup"
      Yast.import "Installation"
    end

    def handle_autoyast(func, param)
      ret = case func
      when "Summary"
        # Create a summary
        summary
      when "Reset"
        # Reset configuration
        @config.reset
        {}
      when "Change"
        # Change configuration
        start_workflow
      when "Import"
        # import configuration
        import(param)
      when "Export"
        # Return the current config
        export
      when "Packages"
        # Return needed packages
        auto_packages
      when "Read"
        log.error "Cloning is not supported by this YaST module"
        false
      when "Write"
        # Write given settings
        write
      when "GetModified"
        @config.modified
      when "SetModified"
        @config.modified = true
        true
      else
        log.error "Unknown function: #{func}"
        raise "Unknown function parameter: #{func}"
      end

      log.info "ret: #{::Registration::Helpers.hide_reg_codes(ret)}"

      ret
    end

    # Get all settings from the first parameter
    # (For use by autoinstallation.)
    # param [Hash] settings The structure to be imported.
    def import(settings)
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

    # Create a textual summary
    # @return [String] summary of the current configuration
    def summary
      ::Registration::Helpers.render_erb_template("autoyast_summary.erb", binding)
    end

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

    # register the system, base product and optional addons
    # return true on success
    def write
      # registration disabled, nothing to do
      return true unless @config.do_registration

      # initialize libzypp if applying settings in installed system or
      # in AutoYast configuration mode ("Apply to System")
      ::Registration::SwMgmt.init if Mode.normal || Mode.config

      return false unless set_registration_url

      # update the registration in AutoUpgrade mode if the old system was registered
      if Mode.update && old_system_registered?
        updated = update_registration
        log.info "Registration updated: #{updated}"
        return updated
      end

      ret = ::Registration::ConnectHelpers.catch_registration_errors do
        import_certificate(@config.reg_server_cert)
        register_base_product && register_addons
      end

      return false unless ret

      finish_registration

      true
    end

    # finish the registration process
    def finish_registration
      # save the registered repositories
      Pkg.SourceSaveAll

      if Mode.normal || Mode.config
        # popup message: registration finished properly
        Popup.Message(_("Registration was successfull."))
      elsif Stage.initial
        # copy the SSL certificate to the target system
        ::Registration::Helpers.copy_certificate_to_target
      end
    end

    # return extra packages needed by this module (none so far)
    # @return [Hash] required packages
    def auto_packages
      ret = { "install" => [], "remove" => [] }
      log.info "Registration needs these packages: #{ret}"
      ret
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
        Report.Error(_("SLP discovery failed, no server found"))
        return nil
      when 1
        return slp_urls.first
      else
        # more than one server found: let the user select, we cannot automatically
        # decide which one to use, asking user in AutoYast mode is not nice
        # but better than aborting the installation...
        return ::Registration::UrlHelpers.slp_service_url
      end
    end

    # download and install the specified SSL certificate to the system
    # @param url [String] URL of the certificate
    def import_certificate(url)
      return unless url && !url.empty?
      log.info "Importing certificate from #{url}..."

      cert = Popup.Feedback(_("Downloading SSL Certificate"), url) do
        ::Registration::SslCertificate.download(url)
      end

      Popup.Feedback(_("Importing SSL Certificate"), cert.subject_name) do
        cert.import
      end
    end

    # UI workflow definition
    def start_workflow
      ::Registration::UI::AutoyastConfigWorkflow.run(@config)
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
      return false unless update_base_product
      return false unless update_addons

      # register additional addons (e.g. originally not present in SLE11)
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
      # register addons
      @config.addons.each do |addon|
        product_service = register_addon(addon)

        ::Registration::Storage::Cache.instance.addon_services << product_service

        registration_ui.disable_update_repos(product_service) if !@config.install_updates
      end

      # install the new products
      ::Registration::SwMgmt.select_addon_products
    end

    def register_addon(addon)
      Popup.Feedback(
        _(CONTACTING_MESSAGE),
        # %s is name of given product
        _("Registering %s ...") % addon["name"]
      ) do
        registration.register_product(addon)
      end
    end

    # was the system already registered?
    # @return [Boolean] true if the system was alreay registered
    def old_system_registered?
      ::Registration::SwMgmt.copy_old_credentials(Installation.destdir)

      # update the registration using the old credentials
      File.exist?(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
    end

    # update the system registration
    # @return [Boolean] true on success
    def update_system_registration
      registration_ui.update_system
    end

    # update the base product registration
    # @return [Boolean] true on success
    def update_base_product
      handle_product_service { registration_ui.update_base_product }
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

    # @return [Boolean] true on success
    # FIXME: share with inst_scc.rb
    def update_addons
      addons = registration_ui.get_available_addons

      failed_addons = registration_ui.update_addons(addons, enable_updates: @config.install_updates)
      failed_addons.empty?
    end
  end unless defined?(SccAutoClient)
end

Yast::SccAutoClient.new.main
