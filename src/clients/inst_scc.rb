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
require "scc_api"

require "cgi"

require "registration/addon"
require "registration/exceptions"
require "registration/helpers"
require "registration/sw_mgmt"
require "registration/repo_state"

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

      # redirect the scc_api log to y2log
      SccApi::GlobalLogger.instance.log = Y2Logger.instance

      @selected_addons = []
      start_workflow
    end

    private

    def register_base_system
      show_scc_credentials_dialog

      ret = nil

      continue_buttons = [:next, :back, :close, :abort]
      while !continue_buttons.include?(ret) do
        ret = UI.UserInput

        if ret == :next
          email = UI.QueryWidget(:email, :Value)
          reg_code = UI.QueryWidget(:reg_code, :Value)
          # reset the user input in case an exception is raised
          ret = nil

          begin
            register(email, reg_code)
            return :next
          rescue SccApi::NoNetworkError
            # Error popup
            Report.Error(_("Network is not configured, the registration server cannot be reached."))
          rescue SccApi::NotAuthorized
            # Error popup
            Report.Error(_("The email address or the registration\ncode is not valid."))
          rescue Timeout::Error
            # Error popup
            Report.Error(_("Connection time out."))
          rescue SccApi::ErrorResponse => e
            # TODO FIXME: display error details from the response
            Report.Error(_("Registration server error.\n\nRetry registration later."))
          rescue SccApi::HttpError => e
            case e.response
            when Net::HTTPClientError
              Report.Error(_("Registration client error."))
            when Net::HTTPServerError
              Report.Error(_("Registration server error.\n\nRetry registration later."))
            else
              Report.Error(_("Registration failed."))
            end
          rescue ::Registration::ServiceError => e
            log.error("Service error: #{e.message % e.service}")
            Report.Error(_(e.message) % e.service)
          rescue ::Registration::PkgError => e
            log.error("Pkg error: #{e.message}")
            Report.Error(_(e.message))
          rescue Exception => e
            log.error("SCC registration failed: #{e}, #{e.backtrace}")
            Report.Error(_("Registration failed."))
          end
        end

        return ret if ret == :skip && confirm_skipping
      end

      return ret
    end

    def register(email, reg_code)
      scc = SccApi::Connection.new(email, reg_code)

      # set the current language to receive translated error messages
      scc.language = ::Registration::Helpers.language

      reg_url = ::Registration::Helpers.registration_url

      if reg_url
        log.info "Using custom registration URL: #{reg_url.inspect}"
        scc.url = reg_url
      end

      # announce (register the system) first
      credentials = run_with_feedback(_("Registering the System..."), _("Contacting the SUSE Customer Center server")) do
        scc.announce
      end

      # ensure the zypp config directories are writable in inst-sys
      ::Registration::SwMgmt.zypp_config_writable!

      # write the global credentials
      credentials.write

      # then register the product(s)
      product_services = run_with_feedback(_("Registering the Product..."), _("Contacting the SUSE Customer Center server")) do
        # there will be just one base product, but theoretically there can be more...
        ::Registration::SwMgmt.products_to_register.map do |base_product|
          log.info("Registering base product: #{base_product.inspect}")
          scc.register(base_product)
        end
      end

      log.info "product_services: #{product_services.inspect}"

      if !product_services.empty?
        Progress.New(
          # TRANSLATORS: dialog caption
          _("Adding Registered Software Repositories"),
          " ",
          product_services.size,
          [ _("Add Services") ],
          [ _("Adding Services") ],
          # TRANSLATORS: dialog help
          _("<p>The repository manager is downloading registered repositories...</p>")
        )

        Progress.NextStage

        begin
          ::Registration::SwMgmt.add_services(product_services, credentials)
        ensure
          Progress.Finish
        end

        # select repositories to use in installation (e.g. enable/disable Updates)
        select_repositories(product_services) if Mode.installation
      end
    end

    def scc_credentials_dialog
      VBox(
        HBox(
          HSpacing(Opt(:hstretch), 3),
          Frame(_("SUSE Customer Center Credentials"),
            MarginBox(1, 0.5,
              VBox(
                MinWidth(32, InputField(Id(:email), _("&Email"))),
                VSpacing(0.5),
                MinWidth(32, InputField(Id(:reg_code), _("Registration &Code")))
              )
            )
          ),
          HSpacing(Opt(:hstretch), 3),
        ),
        VSpacing(3),
        PushButton(Id(:skip), _("&Skip Registration"))
      )
    end

    def scc_help_text
      # TODO: improve the help text
      _("Enter SUSE Customer Center credentials here to register the system to get updates and add-on products.")
    end

    def show_scc_credentials_dialog
      Wizard.SetContents(
        _("SUSE Customer Center Registration"),
        scc_credentials_dialog,
        scc_help_text,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next || Mode.normal
      )
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
          # remember the original state
          repo_state = ::Registration::RepoState.new(repo["SrcId"], repo["enabled"])
          ::Registration::RepoStateStorage.instance.repositories << repo_state

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

    def run_with_feedback(header, label, &block)
      Popup.ShowFeedback(header, label)
      yield
    ensure
      Popup.ClearFeedback
    end

    def addon_selection_items(addons)
      addons.map{|a| Item(Id(a.name), a.label, @selected_addons.include?(a))}
    end

    def addon_selection_dialog_content(addons)
      VBox(
        VWeight(75, MultiSelectionBox(Id(:addons), Opt(:notify), "",
            addon_selection_items(addons))),
        MinHeight(8,
          VWeight(25, RichText(Id(:details), "<small><font color='grey'>" +
                _("Select an addon to show details here") + "</font><small>")),
        ),
        VSpacing(0.4),
        HBox(
          HSpacing(1),
          CheckBox(Id(:media), Opt(:hstretch), _("In&clude Add-on Products from Separate Media")),
        ),
        VSpacing(0.4)
      )
    end

    def show_addon_details(addon)
      details = "<p><big><b>#{CGI.escape_html(addon.label)}</b></big></p><p>#{CGI.escape_html(addon.description)}</p>"
      
      if !addon.depends_on.empty?
        details << _("<p><b>Required Add-ons:</b> %s</p>") % CGI.escape_html(addon.depends_on.map(&:label).join(", "))
      end

      details << _("<p><b>A Registration Key is Required</b></p>") if addon.regkey_needed

      UI.ChangeWidget(Id(:details), :Value, details)
    end

    def handle_addon_selection_dialog(addons)
      ret = nil
      continue_buttons = [:next, :back, :close, :abort, :skip]

      while !continue_buttons.include?(ret) do
        ret = UI.UserInput

        if ret == :addons
          current_addon = UI.QueryWidget(Id(:addons), :CurrentItem)

          if current_addon
            show_addon_details(addons.find{|addon| addon.name == current_addon})
          end
        elsif ret == :next
          # check for the maximum amount of reg. codes supported by Yast
          selected = UI.QueryWidget(Id(:addons), :SelectedItems)
          # maximum number or reg codes which can be displayed in two column layout
          max_supported = 2*MAX_REGCODES_PER_COLUMN

          if addons.select{|a| selected.include?(a.name) && a.regkey_needed}.size > max_supported
            Report.Error(_("YaST allows to select at most %s addons.") % max_supported)
            ret = nil
          end

          @selected_addons = addons.select{|a| selected.include?(a.name)}
          log.info "Selected addons: #{@selected_addons.inspect}"

          ret = :skip if @selected_addons.empty?
        end
      end

      ret
    end

    def select_addons
      addons = get_available_addons
      Wizard.SetContents(
        # dialog title
        _("Available Products and Extensions"),
        addon_selection_dialog_content(addons),
        # FIXME: help text
        "",
        GetInstArgs.enable_back || Mode.normal,
        GetInstArgs.enable_next || Mode.normal
      )

      handle_addon_selection_dialog(addons)

      # TODO register the addons
    end

    def addon_regkey_items(addons)
      textmode = UI.GetDisplayInfo["TextMode"]
      box = VBox()

      addons.each do |addon|
        box[box.size] = MinWidth(32, InputField(Id(addon.name), addon.label))
        # add extra spacing when there are just few addons, in GUI always
        box[box.size] = VSpacing(1) if addons.size < 5 || !textmode
      end

      box
    end

    def addon_regkeys_dialog_content(addons)
      box1 = nil
      box2 = nil

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

    def get_available_addons
      # cache the available addons
      return @available_addons if @available_addons

      run_with_feedback(_("Loading Available Add-on Products and Extensions..."), _("Contacting the SUSE Customer Center server")) do
        # TODO FIXME contact SCC here and query for the available add-ons
        sleep 3

        hae = ::Registration::Addon.new("SUSE_HAE", "12", "x86_64", label: "SLES12 High Availability Extension", description: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus pulvinar sollicitudin mollis. Morbi sit amet purus at purus eleifend elementum in sed tortor. Cras volutpat et augue ac vulputate. Sed pretium eget turpis id sodales. Maecenas ultricies volutpat egestas. Proin ut adipiscing risus")

        @available_addons =
          [
          ::Registration::Addon.new("SUSE_SDK", "12", "x86_64", label: "SLE12 SDK", description: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec molestie felis vel arcu mollis, non dapibus mi dapibus. Duis felis augue, tincidunt quis lectus in, scelerisque aliquam velit. Nam iaculis viverra imperdiet. Cras ac dignissim mi. Duis dignissim quam metus, nec pharetra augue imperdiet et. Sed vel tellus nisl. Fusce a risus nec dui suscipit interdum ut id sapien. Suspendisse nibh velit, ullamcorper nec orci ac, semper bibendum arcu", regkey_needed: false),
          hae,
          ::Registration::Addon.new("SUSE_HAE_GEO", "12", "x86_64", label: "SLES12 High Availability GEO Extension", description: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesent id justo nibh. Cras congue pharetra mauris, vel tincidunt sem commodo a. Morbi in est feugiat, adipiscing purus sed, porttitor metus. Sed sem libero, mollis sed lobortis id, tempor quis tortor. Curabitur posuere ante sed pharetra mollis.", depends_on: [hae])
        ]
      end
    end

    def register_addons()
      missing_regkeys = @selected_addons.select{|a| a.regkey_needed}

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

        ret = UI.UserInput
      end

      # TODO FIXME register the selected addons
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

    def start_workflow
      aliases = {
        "register"        => lambda { register_base_system() },
        "select_addons"   => lambda { select_addons() },
        "register_addons" => lambda { register_addons() }
      }

      sequence = {
        "ws_start" => "register",
        "register"  => {
          :abort   => :abort,
          :skip    => :next,
          :next    => "select_addons"
        },
        "select_addons" => {
          :abort   => :abort,
          :skip    => :next,
          :next => "register_addons"
        },
        "register_addons" => {
          :abort   => :abort,
          :next => :next
        }
      }

      log.info "Starting scc sequence"
      Sequencer.Run(aliases, sequence)
    end
  end
end

Yast::InstSccClient.new.main
