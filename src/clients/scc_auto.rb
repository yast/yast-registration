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
require "registration/helpers"
require "registration/connect_helpers"
require "registration/ssl_certificate"
require "registration/ui/autoyast_config_workflow"

module Yast
  class SccAutoClient < Client
    include Yast::Logger
    include ERB::Util
    extend Yast::I18n

    # popup message
    CONTACTING_MESSAGE = N_("Contacting the Registration Server")

    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "registration"

      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Report"
      Yast.import "Popup"
      Yast.import "Sequencer"

      log.info "scc_auto started"

      @config = ::Registration::Storage::Config.instance
      func = WFM.Args[0]
      param = WFM.Args[1] || {}

      log.info "func: #{func}, param: #{param}"

      case func
      when "Summary"
        # Create a summary
        ret = summary
      when "Reset"
        # Reset configuration
        @config.reset
        ret = {}
      when "Change"
        # Change configuration
        ret = start_workflow
      when "Import"
        # import configuration
        ret = import(param)
      when "Export"
        # Return the current config
        ret = export
      when "Packages"
        # Return needed packages
        ret = auto_packages
      when "Write"
        # Write given settings
        ret = write
      when "GetModified"
        # TODO FIXME: check for changes
        ret = true
      when "SetModified"
        # TODO FIXME: set modified status
      else
        log.error "Unknown function: #{func}"
        raise "Unknown function parameter: #{func}"
      end

      log.info "ret: #{ret}"
      log.info "scc_auto finished"

      ret
    end

    private

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
      # use erb template for rendering the richtext summary
      erb_file = File.expand_path("../../data/registration/autoyast_summary.erb", __FILE__)

      log.info "Loading ERB template #{erb_file}"
      erb = ERB.new(File.read(erb_file))

      # render the ERB template in the context of the current object
      erb.result(binding)
    end

    # register the system, base product and optional addons
    # return true on success
    def write
      # registration disabled, nothing to do
      return true unless @config.do_registration

      # initialize libzypp if applying settings in installed system or
      # in AutoYast configuration mode ("Apply to System")
      ::Registration::SwMgmt.init if Mode.normal || Mode.config

      # set the registration URL
      url = @config.reg_server if @config.reg_server && !@config.reg_server.empty?

      # use SLP discovery
      if !url && @config.slp_discovery
        url = find_slp_server
        return false unless url
      end

      # nil = use the default URL
      @registration = ::Registration::Registration.new(url)

      if @config.reg_server_cert && !@config.reg_server_cert.empty?
        import_certificate(@config.reg_server_cert)
      end

      ret = ::Registration::SccHelpers.catch_registration_errors do
        base_product = ::Registration::SwMgmt.find_base_product
        distro_target = base_product["register_target"]

        if !::Registration::Registration.is_registered?
          log.info "Registering system, distro_target: #{distro_target}"

          Popup.Feedback(_(CONTACTING_MESSAGE),
            _("Registering the System...")) do

            @registration.register(@config.email, @config.reg_code, distro_target)
          end
        end

        # register the base product
        product_service = Popup.Feedback(_(CONTACTING_MESSAGE),
          _("Registering %s ...") % ::Registration::SwMgmt.base_product_label(base_product)
        ) do

          base_product_data = ::Registration::SwMgmt.base_product_to_register
          base_product_data["reg_code"] = @config.reg_code
          @registration.register_product(base_product_data, @config.email)
        end

        disable_update_repos(product_service) if !@config.install_updates

        # register addons
        @config.addons.each do |addon|
          product_service = Popup.Feedback(
            _(CONTACTING_MESSAGE),
            # %s is name of given product
            _("Registering %s ...") % addon["name"]) do

            @registration.register_product(addon)
          end

          disable_update_repos(product_service) if !@config.install_updates
        end
      end

      return false unless ret

      # save the registered repositories
      Pkg.SourceSaveAll

      if Mode.normal || Mode.config
        # popup message: registration finished properly
        Popup.Message(_("Registration was successfull."))
      elsif Stage.initial
        # copy the SSL certificate to the target system
        ::Registration::Helpers.copy_certificate_to_target
      end

      return true
    end

    def auto_packages
      ret = { "install" => [], "remove" => [] }
      log.info "Registration needs these packages: #{ret}"
      ret
    end

    # TODO: share this?
    def disable_update_repos(product_service)
      update_repos = ::Registration::SwMgmt.service_repos(product_service, only_updates: true)
      log.info "Disabling #{update_repos.size} update repositories: #{update_repos}"
      ::Registration::SwMgmt.set_repos_state(update_repos, false)
    end

    # find registration server via SLP
    # @retun [String,nil] URL of the server, nil on error
    def find_slp_server
      # do SLP query
      slp_services = ::Registration::Helpers.slp_discovery_feedback
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
        return ::Registration::Helpers.slp_service_url
      end

    end

    def import_certificate(url)
      log.info "Importing certificate from #{url}..."

      cert = Popup.Feedback(_("Downloading SSL Certificate"), url) do
        ::Registration::SslCertificate.download(url)
      end

      Popup.Feedback(_("Importing SSL Certificate"), cert.subject_name) do
        cert.import_to_system
      end
    end

    # UI workflow definition
    def start_workflow
      ::Registration::UI::AutoyastConfigWorkflow.run(@config)
    end

  end unless defined?(SccAutoClient)
end

Yast::SccAutoClient.new.main
