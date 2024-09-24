# Copyright (c) [2013-2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

# Summary: Ask user for the SCC credentials
#

# use external rubygem for SCC communication
require "yast/suse_connect"

require "cgi"

require "registration/addon"
require "registration/exceptions"
require "registration/finish_dialog"
require "registration/helpers"
require "registration/connect_helpers"
require "registration/sw_mgmt"
require "registration/storage"
require "registration/url_helpers"
require "registration/registration"
require "registration/registration_ui"
require "registration/ui/addon_eula_dialog"
require "registration/ui/addon_selection_registration_dialog"
require "registration/ui/addon_reg_codes_dialog"
require "registration/ui/registered_system_dialog"
require "registration/ui/base_system_registration_dialog"
require "registration/ui/registration_update_dialog"
require "registration/ui/media_addon_workflow"

require "installation/installation_info"
require "y2packager/medium_type"

# TODO: move to the "Registration" name space
module Yast
  class InstSccClient < Client
    include Yast::Logger
    extend Yast::I18n

    # popup message
    CONTACTING_MESSAGE = N_("Contacting the Registration Server")

    def main
      textdomain "registration"
      import_modules

      first_run

      @selected_addons = ::Registration::Storage::InstallationOptions.instance.selected_addons

      initialize_regcodes

      # FIXME: Add a separate client, changing the behavior completely acording to
      # the passed parameters is not nice
      media_workflow? ? ::Registration::UI::MediaAddonWorkflow.run(WFM.Args[1]) : start_workflow
    end

  private

    def import_modules
      Yast.import "UI"
      Yast.import "Popup"
      Yast.import "GetInstArgs"
      Yast.import "Wizard"
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "Label"
      Yast.import "Sequencer"
      Yast.import "Installation"
    end

    # started from the add-on module?
    # @return [Boolean] true if the media add-on worklow should be started
    def media_workflow?
      return false if WFM.Args[0] != "register_media_addon"
      return true if WFM.Args[1].is_a?(Integer)

      log.warn "Invalid argument: #{WFM.Args[1].inspect}, a Fixnum is expected"
      log.warn "Starting the standard workflow"
      false
    end

    # initialize known reg. codes
    def initialize_regcodes
      @known_reg_codes = ::Registration::Storage::RegCodes.instance.reg_codes
      if @known_reg_codes
        log.info "Known reg codes for #{@known_reg_codes.keys.inspect}"
        return
      end

      @known_reg_codes = {}

      # cache the values
      ::Registration::Storage::RegCodes.instance.reg_codes = @known_reg_codes
    end

    # run the dialog for registering the base system
    # @return [Symbol] the user action
    def register_base_system
      base_reg_dialog = ::Registration::UI::BaseSystemRegistrationDialog.new
      ret = base_reg_dialog.run

      if ret == :next
        # remember the created registration object for later use
        @registration = base_reg_dialog.registration

        # disable the BCI repository after registering, it is intended for
        # not registered systems
        Registration::SwMgmt.disable_bci
      end

      # tell #registration_check whether the user wants to go back (bnc#940915)
      @back_from_register = (ret == :back)

      ret
    end

    # run the dialog for updating the registration
    # @return [Symbol] the user action
    def update_registration
      update_dialog = ::Registration::UI::RegistrationUpdateDialog.new
      ret = update_dialog.run

      # remeber the user Registration object to reuse it if needed
      @registration = update_dialog.registration

      ret
    end

    # run the addon selection dialog
    def select_addons
      log.group "Select add-ons" do |group|
        # FIXME: available_addons is called just to fill cache with popup
        return :cancel if get_available_addons == :cancel

        if Registration::Addon.find_all(@registration).empty?
          log.info("Skipping an empty add on selection screen.")
          return :skip
        end

        # FIXME: workaround to reference between old way and new storage in Addon metaclass
        @selected_addons = Registration::Addon.selected
        ::Registration::Storage::InstallationOptions.instance.selected_addons = @selected_addons

        ret = Registration::UI::AddonSelectionRegistrationDialog.run(@registration)

        group.summary = "Selected #{@selected_addons.size} add-ons"
        if !Registration::Addon.auto_selected.empty?
          group.summary += "(+ #{Registration::Addon.auto_selected.size} auto selected)"
        end

        ret
      end
    end

    # load available addons from SCC server
    # the result is cached to avoid reloading when going back and forth in the
    # installation workflow
    def get_available_addons
      # cache the available addons
      return :cancel if init_registration == :cancel

      if !Registration::SwMgmt.find_base_product
        Registration::Helpers.report_no_base_product
        return :cancel
      end

      addons_loaded = Registration::ConnectHelpers.catch_registration_errors do
        registration_ui.get_available_addons
      end

      return :cancel unless addons_loaded

      @addons_registered_orig = Registration::Addon.registered.dup
    end

    # register all selected addons
    # back returns directly to the extensions selection
    def register_addons
      log.group "Register add-ons" do
        return false if init_registration == :cancel

        addons = Registration::Addon.selected + Registration::Addon.auto_selected
        addons = Registration::Addon.registration_order(addons)
        ret = registration_ui.register_addons(addons, @known_reg_codes)
        ret = :extensions if ret == :back
        ret
      end
    end

    # do some sanity checks and decide which workflow will be used
    # return [Symbol] :update
    def registration_check
      # Go back if the user clicked 'back' in the registration dialog
      return :back if @back_from_register

      # check the base product at start to avoid problems later,
      # skip the check on the online medium, it does not contain any repo (or a base product)
      if !(Stage.initial && Y2Packager::MediumType.online?) &&
          ::Registration::SwMgmt.find_base_product.nil?

        ::Registration::Helpers.report_no_base_product
        return Mode.normal ? :abort : :auto
      end

      if Stage.initial
        Wizard.SetContents(
          _("Registration"),
          Empty(),
          # no help text needed, the dialog displays just a progress message
          "",
          false,
          false
        )
      end

      # when managing a system in chroot copy the credentials and the SSL certificate
      # from the chroot to the current system
      if Yast::WFM.scr_chrooted?
        ::Registration::SwMgmt.copy_old_credentials(Installation.destdir)
        ::Registration::SslCertificate.import_from_system
      end

      if Mode.update
        ::Registration::SwMgmt.copy_old_credentials(Installation.destdir)

        if File.exist?(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
          # update the registration using the old credentials
          return :update
        end
      end

      return :register unless ::Registration::Registration.is_registered?

      log.info "The system is already registered, displaying registered dialog"
      # ensure that @registration is initialized
      return :cancel if init_registration == :cancel

      extensions_enabled = true

      success = Registration::ConnectHelpers.catch_registration_errors do
        extensions_enabled = !Registration::Addon.find_all(@registration).empty?
      end

      return :abort unless success

      ::Registration::UI::RegisteredSystemDialog.run(
        extensions:   extensions_enabled,
        registration: ::Registration::Registration.allowed?
      )
    end

    # display EULAs for the selected addons
    def addon_eula
      new_addons = Registration::Addon.selected + Registration::Addon.auto_selected
      ::Registration::UI::AddonEulaDialog.run(new_addons)
    end

    # remember the user entered values so they can be stored to the AutoYast
    # profile generated at the end of installation
    def update_autoyast_config
      options = ::Registration::Storage::InstallationOptions.instance
      return :next unless Mode.installation && options.base_registered

      log.info "Updating Autoyast config"
      config = ::Registration::Storage::Config.instance
      config.import(::Registration::Helpers.collect_autoyast_config(@known_reg_codes))
      config.modified = true
      :next
    end

    # preselect the addon products and in installed system run the package manager
    def pkg_manager
      log.group "Select add-on products to install" do
        ::Registration::SwMgmt.select_addon_products

        # run the package manager only in installed system and if a new addon was registered
        if Mode.normal && Registration::Addon.registered != @addons_registered_orig
          WFM.call("sw_single")
        else
          :next
        end
      end
    end

    # finish the registration workflow
    # @return [symbol] result symbol (:next)
    def finish
      # when managing a system in chroot copy the config file and the SSL certificate
      # to the chroot target
      ::Registration::FinishDialog.new.run("Write") if WFM.scr_chrooted?

      :next
    end

    def registration_ui
      ::Registration::RegistrationUI.new(@registration)
    end

    # define Sequencer aliases
    def workflow_aliases
      {
        # skip this when going back
        "check"                  => lambda do
          log.group("Initialize registration") do
            registration_check
          end
        end,
        "register"               => -> { register_base_system },
        "select_addons"          => -> { select_addons },
        "update"                 => [-> { update_registration }, true],
        "addon_eula"             => -> { addon_eula },
        "register_addons"        => -> { register_addons },
        "update_autoyast_config" => -> { update_autoyast_config },
        "pkg_manager"            => -> { pkg_manager },
        "finish"                 => -> { finish }
      }
    end

    # define the Sequence workflow
    def start_workflow
      sequence = {
        "ws_start"               => workflow_start,
        "check"                  => {
          auto:       :auto,
          abort:      :abort,
          cancel:     :abort,
          register:   "register",
          extensions: "select_addons",
          update:     "update",
          next:       :next
        },
        "update"                 => {
          abort:    :abort,
          cancel:   :abort,
          next:     "select_addons",
          register: "register"
        },
        "register"               => {
          abort:  :abort,
          cancel: :abort,
          skip:   :next,
          next:   "select_addons"
        },
        "select_addons"          => {
          abort:  :abort,
          skip:   "update_autoyast_config",
          cancel: "check",
          next:   "addon_eula"
        },
        "addon_eula"             => {
          abort: :abort,
          next:  "register_addons"
        },
        "register_addons"        => {
          abort:      :abort,
          extensions: "select_addons",
          next:       "update_autoyast_config"
        },
        "update_autoyast_config" => {
          abort: :abort,
          next:  "pkg_manager"
        },
        "pkg_manager"            => {
          abort: :abort,
          next:  "finish"
        },
        "finish"                 => {
          abort: :abort,
          next:  :next
        }
      }

      log.info "Starting scc sequence"
      Sequencer.Run(workflow_aliases, sequence)
    end

    # which dialog should be displayed at start
    def workflow_start
      log.debug "WFM.Args: #{WFM.Args}"

      if WFM.Args.include?("select_extensions") && Registration::Registration.is_registered?
        "select_addons"
      else
        "check"
      end
    end

    # initialize the Registration object
    # @return [Symbol, nil] returns :cancel if the URL selection was canceled
    def init_registration
      return if @registration

      url = ::Registration::UrlHelpers.registration_url
      return :cancel if url == :cancel

      log.info "Initializing registration with URL: #{url.inspect}"
      @registration = ::Registration::Registration.new(url)
    end

    # do some additional initialization at the first run
    def first_run
      return unless ::Registration::Storage::Cache.instance.first_run

      ::Registration::Storage::Cache.instance.first_run = false

      register_installation_info

      return unless Stage.initial && ::Registration::Registration.is_registered?

      ::Registration::Helpers.reset_registration_status
    end

    def register_installation_info
      ::Installation::InstallationInfo.instance.add_callback("registration") do
        options = ::Registration::Storage::InstallationOptions.instance
        cache = ::Registration::Storage::Cache.instance

        {
          "registered"      => ::Registration::Registration.is_registered?,
          "url"             => cache.reg_url,
          "install_updates" => options.install_updates
        }
      end
    end
  end
end
