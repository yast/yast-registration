# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2013 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------
#
# Summary: Ask user for the SCC credentials
#

# use external rubygem for SCC communication
require "yast/suse_connect"

require "cgi"

require "registration/addon"
require "registration/exceptions"
require "registration/helpers"
require "registration/connect_helpers"
require "registration/sw_mgmt"
require "registration/storage"
require "registration/registration"
require "registration/ui/addon_eula_dialog"
require "registration/ui/addon_selection_dialog"

module Yast
  class InstSccClient < Client
    include Yast::Logger
    extend Yast::I18n


    # the maximum number of reg. codes displayed vertically,
    # this is the limit for 80x25 textmode UI
    MAX_REGCODES_PER_COLUMN = 8

    # width of reg code input field widget
    REG_CODE_WIDTH = 33

    # popup message
    CONTACTING_MESSAGE = N_("Contacting the Registration Server")

    def main
      Yast.import "UI"

      textdomain "registration"

      Yast.import "Popup"
      Yast.import "GetInstArgs"
      Yast.import "Wizard"
      Yast.import "Report"
      Yast.import "Mode"
      Yast.import "Label"
      Yast.import "Sequencer"
      Yast.import "Installation"
      Yast.import "ProductControl"
      Yast.import "SourceDialogs"

      @selected_addons = ::Registration::Storage::InstallationOptions.instance.selected_addons

      initialize_regcodes

      start_workflow
    end

    private

    # initialize known reg. codes
    def initialize_regcodes
      @known_reg_codes = ::Registration::Storage::RegCodes.instance.reg_codes
      if @known_reg_codes
        log.info "Known reg codes: #{@known_reg_codes.size} codes"
        return
      end

      @known_reg_codes = {}

      # cache the values
      ::Registration::Storage::RegCodes.instance.reg_codes = @known_reg_codes
    end

    def register_base_system
      show_scc_credentials_dialog

      ret = nil
      @registration_skipped = false

      continue_buttons = [:next, :back, :cancel, :abort]
      while !continue_buttons.include?(ret) do
        ret = UI.UserInput

        case ret
        when :network
          ::Registration::Helpers::run_network_configuration
        when :next
          options = ::Registration::Storage::InstallationOptions.instance

          # do not re-register during installation
          if !Mode.normal && ::Registration::Registration.is_registered? &&
              options.base_registered

            return :next
          end

          email = UI.QueryWidget(:email, :Value)
          reg_code = UI.QueryWidget(:reg_code, :Value)

          # remember the entered values in case user goes back
          options.email = email
          options.reg_code = reg_code

          # reset the user input in case an exception is raised
          ret = nil

          init_registration

          ::Registration::SccHelpers.catch_registration_errors do
            distro_target = ::Registration::SwMgmt.find_base_product["register_target"]

            if !::Registration::Registration.is_registered?
              log.info "Registering system, distro_target: #{distro_target}"

              Popup.Feedback(_(CONTACTING_MESSAGE),
                _("Registering the System...")) do

                @registration.register(email, reg_code, distro_target)
              end
            end

            if !options.base_registered
              # then register the product(s)
              base_product = ::Registration::SwMgmt.base_product_to_register
              product_services = Popup.Feedback(_(CONTACTING_MESSAGE),
                _("Registering %s ...") % ::Registration::SwMgmt.base_product_label(base_product)
              ) do

                base_product["reg_code"] = reg_code
                registered_services = @registration.register_product(base_product)
                options.base_registered = true

                registered_services
              end

              # select repositories to use in installation or update (e.g. enable/disable Updates)
              select_repositories(product_services) if Mode.installation || Mode.update
            end

            return :next
          end
        end

        if ret == :skip && confirm_skipping
          @registration_skipped = true
          return ret
        end
      end

      return ret
    end

    def refresh_base_product
      init_registration

      ::Registration::SccHelpers.catch_registration_errors do
        # then register the product(s)
        base_product = ::Registration::SwMgmt.base_product_to_register
        product_services = Popup.Feedback(
          _(CONTACTING_MESSAGE),
          _("Registering %s ...") % ::Registration::SwMgmt.base_product_label(base_product)
        ) do
          @registration.upgrade_product(base_product)
        end

        # select repositories to use in installation (e.g. enable/disable Updates)
        select_repositories(product_services)
      end
    end

    # display the registration update dialog
    def show_registration_update_dialog
      Wizard.SetContents(
        _("Registration"),
        Label(_("Registration is being updated...")),
        # TODO FIXME
        "",
        GetInstArgs.enable_back,
        GetInstArgs.enable_next || Mode.normal
      )
    end

    def update_registration
      show_registration_update_dialog

      if refresh_base_product
        return :next
      else
        # automatic registration refresh during system upgrade failed, register from scratch
        Report.Error(_("Automatic registration upgrade failed.\n" +
              "You can manually register the system from scratch."))
        return :register
      end
    end

    # content for the main registration dialog
    def scc_credentials_dialog
      base_product = ::Registration::SwMgmt.find_base_product

      options = ::Registration::Storage::InstallationOptions.instance

      # TODO FIXME: still not the final text
      # label text describing the registration (1/2)
      # use \n to split to more lines if needed (use max. 76 chars/line)
      info = _("Please enter a registration or evaluation code for this product and your\n" +
          "User Name/EMail from the SUSE Customer Center in the fields below.\n" +
          "Access to security and general software updates is only possible on\n" +
          "a registered system.")

      if !Mode.normal
        # add a paragraph separator
        info += "\n\n"

        # label text describing the registration (2/2),
        # not displayed in installed system
        # use \n to split to more lines if needed (use max. 76 chars/line)
        info += _("If you skip the registration now be sure to do so in the installed system.")
      end

      registered = ::Registration::Registration.is_registered?

      VBox(
        Mode.installation || Mode.update ?
          Right(PushButton(Id(:network), _("Network Configuration..."))) :
          Empty(),
        VStretch(),
        HSquash(
          VBox(
            VSpacing(1),
            Left(Heading(::Registration::SwMgmt.base_product_label(base_product))),
            VSpacing(1),
            registered ?
              Heading(_("The system is already registered.")) :
              Label(info)
          )
        ),
        VSpacing(UI.TextMode ? 1 : 2),
        HSquash(
          VBox(
            MinWidth(REG_CODE_WIDTH, InputField(Id(:email), _("&Email"), options.email)),
            VSpacing(0.5),
            MinWidth(REG_CODE_WIDTH, InputField(Id(:reg_code), _("Registration &Code"), options.reg_code))
          )
        ),
        VSpacing(UI.TextMode ? 1 : 3),
        registered ? Empty() : PushButton(Id(:skip), _("&Skip Registration")),
        VStretch()
      )
    end

    # help text for the main registration dialog
    def scc_help_text
      # TODO: improve the help text
      _("Enter SUSE Customer Center credentials here to register the system to get updates and add-on products.")
    end

    # display the main registration dialog
    def show_scc_credentials_dialog

      Wizard.SetContents(
        # dialog title
        _("Registration"),
        scc_credentials_dialog,
        scc_help_text,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next || Mode.normal
      )

      registered = ::Registration::Registration.is_registered?
      # disable the input fields when already registered
      if registered && !Mode.normal
        UI.ChangeWidget(Id(:email), :Enabled, false)
        UI.ChangeWidget(Id(:reg_code), :Enabled, false)
      end
    end

    def select_repositories(product_services)
      options = ::Registration::Storage::InstallationOptions.instance

      # added update repositories
      updates = ::Registration::SwMgmt.service_repos(product_services, only_updates: true)
      log.info "Found update repositories: #{updates.size}"

      # not set yet?
      if options.install_updates.nil?
        options.install_updates = Popup.YesNo(
          _("Registration added some update repositories.\n\n" +
              "Do you want to install the latest available\n" +
              "on-line updates during installation?"))
      end

      ::Registration::SwMgmt.set_repos_state(updates, options.install_updates)
    end

    # run the addon selection dialog
    def select_addons
      get_available_addons # FIXME just to fill cache with popup

      # FIXME workaround to reference between old way and new storage in Addon metaclass
      @selected_addons = Registration::Addon.selected
      ::Registration::Storage::InstallationOptions.instance.selected_addons = @selected_addons

      Registration::UI::AddonSelectionDialog.run(@registration)
    end


    # create widgets for entering the addon reg codes
    def addon_regcode_items(addons)
      textmode = UI.TextMode
      box = VBox()

      addons.each do |addon|
        label = addon.short_name
        label << " (#{addon.long_name})" if addon.long_name && !addon.long_name.empty?

        box[box.size] = MinWidth(REG_CODE_WIDTH, InputField(Id(addon.product_ident), label,
            @known_reg_codes.fetch(addon.product_ident, "")))
        # add extra spacing when there are just few addons, in GUI always
        box[box.size] = VSpacing(1) if (addons.size < 5) || !textmode
      end

      box
    end

    # create content for the addon reg codes dialog
    def addon_regcodes_dialog_content(addons)
      # display the second column if needed
      if addons.size > MAX_REGCODES_PER_COLUMN
        # display only the addons which fit two column layout
        display_addons = addons[0..2*MAX_REGCODES_PER_COLUMN - 1]

        # round the half up (more items in the first column for odd number of items)
        half = (display_addons.size + 1) / 2

        box1 = addon_regcode_items(display_addons[0..half - 1])
        box2 = HBox(
          HSpacing(2),
          addon_regcode_items(display_addons[half..-1])
        )
      else
        box1 = addon_regcode_items(addons)
      end

      HBox(
        HSpacing(Opt(:hstretch), 3),
        VBox(
          VStretch(),
          Left(Label(n_(
            "The extension you selected needs a separate registration code.",
            "The extensions you selected need separate registration codes.",
            addons.size
          ))),
          Left(Label(n_(
            "Enter the registration code into the field below.",
            "Enter the registration codes into the fields below.",
            addons.size
          ))),
          VStretch(),
          HBox(
            box1,
            box2 ? box2 : Empty()
          ),
          VStretch()
        ),
        HSpacing(Opt(:hstretch), 3)
      )
    end

    # load available addons from SCC server
    # the result is cached to avoid reloading when going back and forth in the
    # installation workflow
    def get_available_addons
      # cache the available addons
      init_registration

      @available_addons = Popup.Feedback(
        _(CONTACTING_MESSAGE),
        _("Loading Available Add-on Products and Extensions...")) do

        Registration::Addon.find_all(@registration)
      end

      ::Registration::Storage::Cache.instance.available_addons = @available_addons
      @available_addons
    end

    # handle user input in the addon reg codes dialog
    def handle_register_addons_dialog(addons_with_codes)
      continue_buttons = [:next, :back, :close, :abort]

      ret = nil
      while !continue_buttons.include?(ret) do
        ret = UI.UserInput

        if ret == :next
          collect_addon_regcodes(addons_with_codes)

          # register the add-ons
          ret = nil unless register_selected_addons
        end
      end

      return ret
    end

    # collect the entered reg codes from UI
    # @return [Hash<Addon,String>] addon => reg. code mapping
    def collect_addon_regcodes(addons_with_codes)
      pairs = addons_with_codes.map do |a|
        [a.product_ident, UI.QueryWidget(Id(a.product_ident), :Value)]
      end
      @known_reg_codes.merge!(Hash[pairs])
    end

    # register all selected addons
    def register_selected_addons
      registration_order = @selected_addons.clone #create duplicate as array is modified in loop for registration order
      # TODO FIXME: SCC does not report dependoencies
      #      begin
      #        # compute the registration order according to the dependencies
      #        registration_order = Registration::AddonSorter.registration_order(@selected_addons)
      #      rescue KeyError
      #        # Continuew/Cancel dialog: missing dependency error
      #        if Popup.ContinueCancel(_("Addon dependencies cannot be solved.\n" +
      #                "Register without solving dependencies?"))
      #          # just try the current order it might work
      #        else
      #          return false
      #        end
      #      end
      #
      # log.info "Addon registration order: #{registration_order.map(&:short_name)}"

      init_registration

      product_succeed = registration_order.map do |product|
        ::Registration::SccHelpers.catch_registration_errors("#{product.short_name}:") do
          product_service = Popup.Feedback(
            _(CONTACTING_MESSAGE),
            # %s is name of given product
            _("Registering %s ...") % product.short_name) do

            product_data = {
              "name" => product.product_ident,
              "reg_code" => @known_reg_codes[product.product_ident],
              "arch" => product.arch,
              "version" => product.version
            }

            @registration.register_product(product_data)
          end

          # select repositories to use in installation (e.g. enable/disable Updates)
          select_repositories(product_service) if Mode.installation || Mode.update

          # move from selected to registered
          registered_addons << product.product_ident
          @selected_addons.reject!{|selected| selected.product_ident == product.product_ident}
        end
      end

      return !product_succeed.include?(false) # succeed only if noone failed
    end

    # run the addon reg codes dialog
    def register_addons
      missing_regcodes = @selected_addons.reject(&:free)

      # if registering only add-ons which do not need a reg. code (like SDK)
      # then simply start the registration
      if missing_regcodes.empty?
        Wizard.SetContents(
          # dialog title
          _("Register Extensions and Modules"),
          # display only the products which need a registration code
          Empty(),
          # FIXME: help text
          "",
          false,
          false
        )
        # when registration fails go back
        return register_selected_addons ? :next : :back
      else
        Wizard.SetContents(
          # dialog title
          _("Extension and Module Registration Codes"),
          # display only the products which need a registration code
          addon_regcodes_dialog_content(missing_regcodes),
          # FIXME: help text
          "",
          GetInstArgs.enable_back || Mode.normal,
          GetInstArgs.enable_next || Mode.normal
        )

        return handle_register_addons_dialog(missing_regcodes)
      end
    end

    def confirm_skipping
      # Popup question: confirm skipping the registration
      confirmation = _("If you do not register your system we will not be able\n" +
          "to grant you access to the update repositories.\n\n" +
          "You can register after the installation or visit our\n" +
          "Customer Center for online registration.\n\n" +
          "Really skip the registration now?")

      Popup.YesNo(confirmation)
    end

    def media_addons
      # force displaying the UI
      Installation.add_on_selected = true

      ret = WFM.call("inst_add-on",
        [{ "enable_next" => true, "enable_back" => true}]
      )
      ret = :next if [:auto, :finish].include?(ret)

      # leave the workflow if registration was skipped
      ret = :finish if ret == :next && @registration_skipped

      return ret
    end

    def registered_dialog
      VBox(
        Heading(_("The system is already registered.")),
        VSpacing(2),
        # button label
        PushButton(Id(:register), _("Register Again")),
        VSpacing(1),
        # button label
        PushButton(Id(:extensions), _("Select Extensions"))
      )
    end

    def display_registered_dialog
      Wizard.SetContents(
        # dialog title
        _("Registration"),
        registered_dialog,
        # FIXME: help text
        "",
        GetInstArgs.enable_back || Mode.normal,
        GetInstArgs.enable_back || Mode.normal
      )

      Wizard.SetNextButton(:next, Label.FinishButton) if Mode.normal

      continue_buttons = [:next, :back, :cancel, :abort, :register, :extensions]

      ret = nil
      while !continue_buttons.include?(ret) do
        ret = UI.UserInput
      end

      Wizard.RestoreNextButton

      return ret
    end

    def registration_check
      # check the base product at start to avoid problems later
      if ::Registration::SwMgmt.find_base_product.nil?
        # error message
        Report.Error(_("The base product was not found,\ncheck your system."))
        return Mode.normal ? :abort : :auto
      end

      if Mode.update
        Wizard.SetContents(
          _("Registration"),
          Empty(),
          "",
          false,
          false
        )

        ::Registration::SwMgmt.copy_old_credentials(Installation.destdir)

        if File.exists?(::Registration::Registration::SCC_CREDENTIALS)
          # update the registration using the old credentials
          return :update
        end
      end

      if Mode.normal && ::Registration::Registration.is_registered?
        return display_registered_dialog
      else
        return :register
      end
    end

    def addon_eula
      ::Registration::UI::AddonEulaDialog.run(@selected_addons)
    end

    # UI workflow definition
    def start_workflow
      aliases = {
        # skip this when going back
        "check"           => [ lambda { registration_check() }, true ],
        "register"        => lambda { register_base_system() },
        "select_addons"   => lambda { select_addons() },
        "update"          => [ lambda { update_registration() }, true ],
        "media_addons"    => lambda { media_addons() },
        "addon_eula"      => lambda { addon_eula() },
        "register_addons" => lambda { register_addons() }
      }

      sequence = {
        "ws_start" => "check",
        "check" => {
          :auto       => :auto,
          :abort      => :abort,
          :cancel     => :abort,
          :register   => "register",
          :extensions => "select_addons",
          :update     => "update",
          :next       => :next
        },
        "update" => {
          :abort   => :abort,
          :cancel   => :abort,
          :next => "select_addons",
          :register => "register",
        },
        "register" => {
          :abort    => :abort,
          :cancel   => :abort,
          :skip     => "media_addons",
          :next     => "select_addons"
        },
        "select_addons" => {
          :abort    => :abort,
          :skip     => "media_addons",
          :next     => "media_addons"
        },
        "media_addons" => {
          :abort    => :abort,
          :next     => "addon_eula",
          :finish   => :next
        },
        "addon_eula" => {
          :abort    => :abort,
          :next     => "register_addons"
        },
        "register_addons" => {
          :abort    => :abort,
          :next     => :next
        }
      }

      log.info "Starting scc sequence"
      Sequencer.Run(aliases, sequence)
    end

    def init_registration
      if !@registration
        url = ::Registration::Helpers.registration_url
        @registration = ::Registration::Registration.new(url)
      end
    end

    # helper method for accessing the registered addons
    def registered_addons
      Registration::Addon.registered
    end

  end unless defined?(InstSccClient)
end

Yast::InstSccClient.new.main
