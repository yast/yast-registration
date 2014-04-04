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
require "yast/scc_api"

require "cgi"

require "registration/exceptions"
require "registration/helpers"
require "registration/scc_helpers"
require "registration/sw_mgmt"
require "registration/storage"
require "registration/registration"

module Yast
  class InstSccClient < Client
    include Yast::Logger

    # the maximum number of reg. codes displayed vertically,
    # this is the limit for 80x25 textmode UI
    MAX_REGCODES_PER_COLUMN = 9

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

      @selected_addons = ::Registration::Storage::InstallationOptions.instance.selected_addons

      initialize_regkeys

      start_workflow
    end

    private

    # initialize known reg. keys
    def initialize_regkeys
      @known_reg_keys = ::Registration::Storage::RegKeys.instance.reg_keys
      if @known_reg_keys
        log.info "Known reg keys: #{@known_reg_keys.size} keys"
        return
      end

      if !Mode.normal
        # read registration keys from USB media
        log.info "Reading keys from USB media..."
        # TODO FIXME: placeholder for FATE#316796 (https://fate.suse.com/316796)
        # read the keys here, return Hash with mapping product_name => reg_key
        @known_reg_keys = {}
        log.info "Found #{@known_reg_keys.size} keys"
      else
        log.info "Initializing empty known reg keys"
        @known_reg_keys = {}
      end

      # cache the values
      ::Registration::Storage::RegKeys.instance.reg_keys = @known_reg_keys
    end

    def register_base_system
      show_scc_credentials_dialog

      ret = nil

      continue_buttons = [:next, :back, :cancel, :abort]
      while !continue_buttons.include?(ret) do
        ret = UI.UserInput

        case ret
        when :network
          ::Registration::Helpers::run_network_configuration
        when :next
          # do not re-register during installation
          return :next if ::Registration::Registration.is_registered? && !Mode.normal

          email = UI.QueryWidget(:email, :Value)
          reg_code = UI.QueryWidget(:reg_code, :Value)

          # remember the entered values in case user goes back
          options = ::Registration::Storage::InstallationOptions.instance
          options.email = email
          options.reg_code = reg_code

          # reset the user input in case an exception is raised
          ret = nil

          url = ::Registration::Helpers.registration_url
          @registration = ::Registration::Registration.new(url)

          ::Registration::SccHelpers.catch_registration_errors do
            Popup.Feedback(_("Registering the System..."),
              _("Contacting the SUSE Customer Center server")) do

              @registration.register(email, reg_code)
            end

            # then register the product(s)
            base_product = ::Registration::SwMgmt.base_product_to_register
            product_services = Popup.Feedback(
              _("Registering Product..."),
              _("Contacting the SUSE Customer Center server")) do

              @registration.register_products([base_product])
            end

            # remember the base products for later (to get the respective addons)
            ::Registration::Storage::BaseProduct.instance.product = base_product

            # select repositories to use in installation (e.g. enable/disable Updates)
            select_repositories(product_services) if Mode.installation

            return :next
          end
        end

        return ret if ret == :skip && confirm_skipping
      end

      return ret
    end

    # content for the main registration dialog
    def scc_credentials_dialog
      base_product = ::Registration::SwMgmt.find_base_product
      base_product_name = base_product["display_name"] ||
        base_product["short_name"] ||
        base_product["name"] ||
        _("Unknown product")

      options = ::Registration::Storage::InstallationOptions.instance

      # TODO FIXME: still not the final text
      # label text describing the registration (1/2)
      # use \n to split to more lines if needed (use max. 76 chars/line)
      info = _("Please enter a registration or evaluation code for this product and your\n" +
          "User Name/EMail from the SUSE Customer Center in the fields below.\n" +
          "Access to security and general software updates is only possible on\n" +
          "a registered system.")

      if !Mode.normal || true
        # add a paragraph separator
        info << "\n\n"

        # label text describing the registration (2/2),
        # not displayed in installed system
        # use \n to split to more lines if needed (use max. 76 chars/line)
        info << _("If you skip the registration now be sure to do so in the installed system.")
      end

      VBox(
        Mode.installation ?
          Right(PushButton(Id(:network), _("Network Configuration..."))) :
          Empty(),
        VStretch(),
        HSquash(
          VBox(
            VSpacing(1),
            Left(Heading(base_product_name)),
            VSpacing(1),
            Label(info)
          )
        ),
        VSpacing(UI.TextMode ? 1 : 2),
        HSquash(
          VBox(
            MinWidth(33, InputField(Id(:email), _("&Email"), options.email)),
            VSpacing(0.5),
            MinWidth(33, InputField(Id(:reg_code), _("Registration &Code"), options.reg_code))
          )
        ),
        VSpacing(UI.TextMode ? 1 : 3),
        Mode.normal ? Empty() : PushButton(Id(:skip), _("&Skip Registration")),
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
      registered = ::Registration::Registration.is_registered?

      Wizard.SetContents(
        # dialog title
        _("Registration"),
        scc_credentials_dialog,
        scc_help_text,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next || Mode.normal
      )

      # disable the input fields when already registered
      if registered && !Mode.normal
        UI.ChangeWidget(Id(:email), :Enabled, false)
        UI.ChangeWidget(Id(:reg_code), :Enabled, false)
      end
    end

    def repo_items(repos)
      repos.map{|repo| Item(Id(repo["SrcId"]), repo["name"], repo["enabled"])}
    end

    def repo_selection_dialog(repos)
      label = _("You can manually change the repository states,\n" +
          "select repositories which will be used for installation.")

      VBox(
        Heading(_("Repository State")),
        VSpacing(0.5),
        Label(label),
        MultiSelectionBox(Id(:repositories), "", repo_items(repos)),
        VSpacing(0.5),
        HBox(
          PushButton(Id(:ok), Opt(:default), Label.OKButton),
          PushButton(Id(:cancel), Label.CancelButton)
        )
      )
    end

    def activate_repo_settings(repos)
      selected_items = UI.QueryWidget(Id(:repositories), :SelectedItems)
      log.info "Selected items: #{selected_items.inspect}"

      repos.each do |repo|
        repo_id = repo["SrcId"]
        enabled = selected_items.include?(repo["SrcId"])

        if repo["enabled"] != enabled
          log.info "Changing repository state: #{repo["name"]} enabled: #{enabled}"
          Pkg.SourceSetEnabled(repo_id, enabled)
        end
      end
    end

    def select_repositories(product_services)
      repos = ::Registration::SwMgmt.service_repos(product_services)

      UI.OpenDialog(repo_selection_dialog(repos))
      UI.SetFocus(:ok)

      begin
        ret = UI.UserInput
        activate_repo_settings(repos) if ret == :ok
      ensure
        UI.CloseDialog
      end
    end

    # create item list (available addons items)
    def addon_selection_items(addons)
      box = VBox()

      # whether to add extra spacing in the UI
      add_extra_spacing = (addons.size < 5) || !UI.TextMode

      addons.each do |addon|
        label = addon.short_name
        label << " (#{addon.long_name})" if !addon.long_name.empty?

        box[box.size] = Left(CheckBox(Id(addon.product_ident), Opt(:notify),
            addon.short_name, @selected_addons.include?(addon)))

        # add extra spacing when there are just few addons, in GUI always
        box[box.size] = VSpacing(0.7) if add_extra_spacing
      end

      box
    end

    # create content fot the addon selection dialog
    def addon_selection_dialog_content(addons)
      media_checkbox = Empty()

      # the media check box is displayed only at installation
      # to modify the installation workflow (display extra add-on dialog)
      if Mode.installation
        media_checkbox = VBox(
          VSpacing(0.4),
          HBox(
            HSpacing(1),
            Left(CheckBox(Id(:media), _("In&clude Add-on Products from Separate Media"),
                Installation.add_on_selected)),
          )
        )
      end

      # less lines in textmode to fit 80x25 size
      lines = UI.TextMode ? 9 : 14

      # use two column layout if needed
      vbox1 = addon_selection_items(addons[0..(lines - 1)])
      vbox2 = (addons.size > lines) ? HBox(
        HSpacing(1),
        VBox(
          addon_selection_items(addons[lines..(2*lines - 1)]),
          VStretch()
        )
      ) :
        Empty()

      VBox(
        VStretch(),
        Left(Heading(_("Available Extensions"))),
        VWeight(75, MarginBox(2, 1, HBox(
              vbox1,
              vbox2
            ))),
        Left(Label(_("Details"))),
        MinHeight(8,
          VWeight(25, RichText(Id(:details), Opt(:disabled), "<small>" +
                _("Select an addon to show details here") + "</small>")),
        ),
        media_checkbox,
        VSpacing(0.4),
        VStretch()
      )
    end

    # update addon details after changing the current addon in the UI
    def show_addon_details(addon)
      # addon description is a rich text
      UI.ChangeWidget(Id(:details), :Value, addon.description)
      UI.ChangeWidget(Id(:details), :Enabled, true)
    end

    # check addon dependencies and automatically select required addons
    def check_addon_dependencies(addons)
      selected = UI.QueryWidget(Id(:addons), :SelectedItems)
      selected_addons = addons.select{|a| selected.include?(a.name)}

      selected_addons.each do |a|
        missing = a.required_addons - selected_addons

        if !missing.empty?
          # popup message, %s are product names
          Popup.Message((_("Automatically selecting '%s'\ndependencies:\n\n%s") %
              [a.label, missing.map(&:label).join("\n")]))
          # select the missing entries
          UI.ChangeWidget(Id(:addons), :SelectedItems, selected + missing.map(&:name))
        end
      end
    end

    # check for the maximum amount of reg. codes supported by Yast
    def supported_addon_count(selected)
      # maximum number or reg codes which can be displayed in two column layout
      max_supported = 2*MAX_REGCODES_PER_COLUMN

      # check the addons requiring a reg. code
      if selected.select{|a| !a.free}.size > max_supported
        Report.Error(_("YaST allows to select at most %s addons.") % max_supported)
        return false
      end

      return true
    end

    # read the addon media checkbox and adapt the installation workflow accordingly
    def set_media_addons
      if Mode.installation
        # the widget exists only at installation
        Installation.add_on_selected = UI.QueryWidget(Id(:media), :Value)
        log.info "Add-on media selected: #{Installation.add_on_selected}"

        # lazy include, the file is part of yast2-installation
        # avoid yast2-installation runtime dependency by including it only here,
        # not at the global level
        Yast.include self, "installation/misc.rb"
        AdjustStepsAccordingToInstallationSettings()
      end
    end

    # handle user input in the addon selection dialog
    def handle_addon_selection_dialog(addons)
      ret = nil
      continue_buttons = [:next, :back, :close, :abort, :skip]

      while !continue_buttons.include?(ret) do
        ret = UI.UserInput

        case ret
        when :next
          selected = addons.select{|a| UI.QueryWidget(Id(a.product_ident), :Value)}

          if !supported_addon_count(selected)
            ret = nil
            next
          end

          @selected_addons = selected
          ::Registration::Storage::InstallationOptions.instance.selected_addons = @selected_addons
          log.info "Selected addons: #{@selected_addons.map(&:short_name)}"

          set_media_addons

          ret = :skip if @selected_addons.empty?
        else
          # check whether it's an add-on ID (checkbox clicked)
          addon = addons.find{|addon| addon.product_ident == ret}

          # an addon has been changed, refresh details, check dependencies
          if addon
            show_addon_details(addon)
            # TODO FIXME: SCC does not support dependencies yet
            # check_addon_dependencies(addons)
          end
        end
      end

      ret
    end

    # run the addon selection dialog
    def select_addons
      addons = get_available_addons
      Wizard.SetContents(
        # dialog title
        _("Extension Selection"),
        addon_selection_dialog_content(addons),
        # help text for add-ons installation, %s is URL
        _("<p>\nTo install an add-on product from separate media together with &product;, select\n" +
            "<b>Include Add-on Products from Separate Media</b>.</p>\n" +
            "<p>If you need specific hardware drivers for installation, see <i>%s</i> site.</p>") %
        "http://drivers.suse.com",
        GetInstArgs.enable_back || Mode.normal,
        GetInstArgs.enable_next || Mode.normal
      )

      handle_addon_selection_dialog(addons)
    end


    # create widgets for entering the addon reg keys
    def addon_regkey_items(addons)
      textmode = UI.TextMode
      box = VBox()

      addons.each do |addon|
        label = addon.short_name
        label << " (#{addon.long_name})" unless addon.long_name.empty?

        box[box.size] = MinWidth(32, InputField(Id(addon.product_ident), label,
            @known_reg_keys.fetch(addon.product_ident, "")))
        # add extra spacing when there are just few addons, in GUI always
        box[box.size] = VSpacing(1) if (addons.size < 5) || !textmode
      end

      box
    end

    # create content for the addon reg keys dialog
    def addon_regkeys_dialog_content(addons)
      # display the second column if needed
      if addons.size > MAX_REGCODES_PER_COLUMN
        # display only the addons which fit two column layout
        display_addons = addons[0..2*MAX_REGCODES_PER_COLUMN - 1]

        # round the half up (more items in the first column for odd number of items)
        half = (display_addons.size + 1) / 2

        box1 = addon_regkey_items(display_addons[0..half - 1])
        box2 = HBox(
          HSpacing(2),
          addon_regkey_items(display_addons[half..-1])
        )
      else
        box1 = addon_regkey_items(addons)
      end

      HBox(
        HSpacing(Opt(:hstretch), 3),
        box1,
        box2 ? box2 : Empty(),
        HSpacing(Opt(:hstretch), 3)
      )
    end

    # load available addons from SCC server
    # the result is cached to avoid reloading when going back and forth in the
    # installation workflow
    def get_available_addons
      # cache the available addons
      return @available_addons if @available_addons

      @available_addons = Popup.Feedback(
        _("Loading Available Add-on Products and Extensions..."),
        _("Contacting the SUSE Customer Center server")) do

        @registration.get_addon_list
      end

      log.info "Received product extensions: #{@available_addons}"
      @available_addons
    end

    # handle user input in the addon reg keys dialog
    def handle_register_addons_dialog(addons_with_keys)
      continue_buttons = [:next, :back, :close, :abort]

      ret = nil
      while !continue_buttons.include?(ret) do
        ret = UI.UserInput

        if ret == :next
          collect_addon_regkeys(addons_with_keys)

          # register the add-ons
          ret = nil unless register_selected_addons
        end
      end

      return ret
    end

    # collect the entered reg keys from UI
    # @return [Hash<Addon,String>] addon => reg. code mapping
    def collect_addon_regkeys(addons_with_keys)
      pairs = addons_with_keys.map do |a|
        [a.product_ident, UI.QueryWidget(Id(a.product_ident), :Value)]
      end
      @known_reg_keys.merge!(Hash[pairs])
    end

    # register all selected addons
    def register_selected_addons
      registration_order = @selected_addons
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

      products = registration_order.map do |a|
        {
          "name" => a.product_ident,
          "reg_key" => @known_reg_keys[a.product_ident],
          # TODO FIXME: not handled by SCC yet
          "arch" => nil,
          "version" => nil
        }
      end

      ret = ::Registration::SccHelpers.catch_registration_errors do
        product_services = Popup.Feedback(
          n_("Registering Product...", "Registering Products...", products.size),
          _("Contacting the SUSE Customer Center server")) do

          @registration.register_products(products)
        end

        # select repositories to use in installation (e.g. enable/disable Updates)
        select_repositories(product_services) if Mode.installation

        return true
      end

      return ret
    end

    # run the addon reg keys dialog
    def register_addons
      missing_regkeys = @selected_addons.reject(&:free)

      # if registering only add-ons which do not need a reg. key (like SDK)
      # then simply start the registration
      if missing_regkeys.empty?
        Wizard.SetContents(
          # dialog title
          _("Registering Selected Add-on Products and Extensions"),
          # display only the products which need a registration key
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
          _("Enter Registration Keys for Selected Add-on Products and Extensions"),
          # display only the products which need a registration key
          addon_regkeys_dialog_content(missing_regkeys),
          # FIXME: help text
          "",
          GetInstArgs.enable_back || Mode.normal,
          GetInstArgs.enable_next || Mode.normal
        )

        return handle_register_addons_dialog(missing_regkeys)
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
      if Installation.add_on_selected
        # start the next step (add-on media selection)
        ProductControl.RunFrom(ProductControl.CurrentStep + 1, false)
      else
        :next
      end
    end

    def registered_dialog
      VBox(
        Heading(_("The system is already registered.")),
        VSpacing(1),
        Label(_("Note: Registering your system again will\n" +
              "consume an additional subscription.")),
        VSpacing(1),
        PushButton(Id(:register), _("Register Again"))
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

      continue_buttons = [:next, :back, :cancel, :abort, :register]

      ret = nil
      while !continue_buttons.include?(ret) do
        ret = UI.UserInput
      end

      return ret
    end

    def registration_check
      if Mode.normal && ::Registration::Registration.is_registered?
        return display_registered_dialog
      else
        return :register
      end
    end

    # UI workflow definition
    def start_workflow
      aliases = {
        "register"        => lambda { register_base_system() },
        "select_addons"   => lambda { select_addons() },
        "register_addons" => lambda { register_addons() },
        "media_addons"    => lambda { media_addons() },
        # skip this when going back
        "check"           => [ lambda { registration_check() }, true ]
      }

      sequence = {
        "ws_start" => "check",
        "check" => {
          :abort    => :abort,
          :cancel   => :abort,
          :register => "register",
          :next     => :next
        },
        "register" => {
          :abort    => :abort,
          :cancel   => :abort,
          :skip     => :next,
          :next     => "select_addons"
        },
        "select_addons" => {
          :abort    => :abort,
          :skip     => "media_addons",
          :next     => "register_addons"
        },
        "register_addons" => {
          :abort    => :abort,
          :next     => "media_addons"
        },
        "media_addons" => {
          :abort    => :abort,
          :next     => :next
        }
      }

      log.info "Starting scc sequence"
      Sequencer.Run(aliases, sequence)
    end
  end unless defined?(InstSccClient)
end

Yast::InstSccClient.new.main
