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
require "registration/ui/autoyast_addon_dialog"
require "registration/ui/autoyast_config_dialog"
require "registration/ui/addon_selection_dialog"
require "registration/ui/addon_eula_dialog"
require "registration/ui/addon_reg_codes_dialog"

module Yast
  class SccAutoClient < Client
    include Yast::Logger
    include ERB::Util

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

      # TODO FIXME: import the server certificate
      if @config.reg_server_cert

      end

      ret = ::Registration::SccHelpers.catch_registration_errors do
        # register the system
        Popup.Feedback(_("Registering the System..."),
          _("Contacting the SUSE Customer Center server")) do

          @registration.register(@config.email, @config.reg_code)
        end

        # register the base product
        products = ::Registration::SwMgmt.base_products_to_register
        Popup.Feedback(
          n_("Registering Product...", "Registering Products...", products.size),
          _("Contacting the SUSE Customer Center server")) do

          @registration.register_products(products)
        end

        # register addons if configured
        if !@config.addons.empty?
          addon_products = @config.addons.map do |a|
            {
              "name" => a["name"],
              "reg_code" => a["reg_code"],
              "arch" => a["arch"],
              "version" => a["version"],
              "release_type" => a["release_type"],
            }
          end

          # register addons
          Popup.Feedback(
            n_("Registering Product...", "Registering Products...", addon_products.size),
            _("Contacting the SUSE Customer Center server")) do

            @registration.register_products(addon_products)
          end
        end
      end

      return false unless ret

      # disable updates
      if !@config.install_updates
        # TODO FIXME: disable Update repositories
      end

      # save the registered repositories
      Pkg.SourceSaveAll

      if Mode.normal || Mode.config
        # popup message: registration finished properly
        Popup.Message(_("Registration was successfull."))
      else
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

    # ---------------------------------------------------------

    def select_addons
      ::Registration::UI::AutoyastAddonDialog.run(@config.addons)
    end

    def select_remote_addons
      if !::Registration::SwMgmt.init
        Report.Error(Pkg.LastError)
        return :abort
      end

      url = ::Registration::Helpers.registration_url
      registration = ::Registration::Registration.new(url)
      ::Registration::UI::AddonSelectionDialog.run(registration)
    end

    def addons_eula
      ::Registration::UI::AddonEulaDialog.run(::Registration::Addon.selected)
    end

    def addons_reg_codes
      known_reg_codes = Hash[@config.addons.map{|a| [a["name"], a["reg_code"]]}]

      if !::Registration::Addon.selected.all?(&:free)
        ret = ::Registration::UI::AddonRegCodesDialog.run(::Registration::Addon.selected, known_reg_codes)
        return ret unless ret == :next
      end

      ::Registration::Addon.selected.each do |addon|
        new_addon = {
          "name" => addon.identifier,
          "version" => addon.version,
          "arch" => addon.arch,
          "release_type" => addon.release_type,
          "reg_code" => known_reg_codes[addon.identifier] || ""
        }

        # already known?
        config_addon = @config.addons.find{ |a|
          a["name"] == new_addon["name"] &&  a["version"] == new_addon["version"] &&
            a["arch"] == new_addon["arch"] && a["release_type"] == new_addon["release_type"]
        }

        # add or edit
        if config_addon
          config_addon.merge!(new_addon)
        else
          @config.addons << new_addon
        end
      end

      :next
    end

    def configure_registration
      ::Registration::UI::AutoyastConfigDialog.run(@config)
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

    # UI workflow definition
    def start_workflow
      aliases = {
        "general"         => lambda { configure_registration() },
        "addons"          => [ lambda { select_addons() }, true ],
        "remote_addons"   => [ lambda { select_remote_addons() }, true ],
        "addons_eula"     => [ lambda { addons_eula() }, true ],
        "addons_regcodes" => [ lambda { addons_reg_codes() }, true ]
      }

      sequence = {
        "ws_start" => "general",
        "general"  => {
          :abort   => :abort,
          :next    => :next,
          :addons  => "addons"
        },
        "addons" => {
          :abort   => :abort,
          :next    => "general",
          :download => "remote_addons"
        },
        "remote_addons" => {
          :abort   => :abort,
          :next    => "addons_eula"
        },
        "addons_eula" => {
          :abort   => :abort,
          :next    => "addons_regcodes"
        },
        "addons_regcodes" => {
          :abort   => :abort,
          :next    => "addons"
        }
      }

      log.info "Starting scc_auto sequence"
      Sequencer.Run(aliases, sequence)
    end

  end unless defined?(SccAutoClient)
end

Yast::SccAutoClient.new.main
