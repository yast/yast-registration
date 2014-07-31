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

    def set_addon_table_content(current = nil)
      content = @config.addons.map do |a|
        Item(Id(a["name"]), a["name"], a["version"], a["arch"],
          a["release_type"],  a["reg_code"])
      end

      UI.ChangeWidget(Id(:addons_table), :Items, content)
      UI.ChangeWidget(Id(:addons_table), :CurrentItem, current) if current
    end

    def display_addon_popup(name: "", version: "", arch: "", release_type: "",
        reg_code: "")
      content = VBox(
        InputField(Id(:name), _("Extension or Module &Identifier"), name),
        InputField(Id(:version), _("&Version"), version),
        InputField(Id(:arch), _("&Architecture"), arch),
        InputField(Id(:release_type), _("&Release Type"), release_type),
        InputField(Id(:reg_code), _("Registration &Code"), reg_code),
        VSpacing(1),
        HBox(
          PushButton(Id(:ok), Label.OKButton),
          PushButton(Id(:cancel), Label.CancelButton)
        )
      )

      UI.OpenDialog(content)

      begin
        ui = UI.UserInput

        if ui == :ok
          return {
            "name" => UI.QueryWidget(Id(:name), :Value),
            "version" => UI.QueryWidget(Id(:version), :Value),
            "arch" => UI.QueryWidget(Id(:arch), :Value),
            "release_type" => UI.QueryWidget(Id(:release_type), :Value),
            "reg_code" => UI.QueryWidget(Id(:reg_code), :Value)
          }
        else
          return nil
        end
      ensure
        UI.CloseDialog
      end
    end

    def delete_addon
      selected = UI.QueryWidget(Id(:addons_table), :CurrentItem)
      if selected && Popup.YesNo(_("Really delete '%s'?") % selected)
        @config.addons.reject!{|a| a["name"] == selected}
        set_addon_table_content
      end
    end

    def edit_addon
      selected = UI.QueryWidget(Id(:addons_table), :CurrentItem)
      if selected
        addon = @config.addons.find{|a| a["name"] == selected}

        ret = display_addon_popup(
          name: selected,
          version: addon["version"],
          arch: addon["arch"],
          release_type: addon["release_type"],
          reg_code: addon["reg_code"]
        )

        if ret
          addon["name"] = ret["name"]
          addon["version"] = ret["version"]
          addon["arch"] = ret["arch"]
          addon["release_type"] = ret["release_type"]
          addon["reg_code"] = ret["reg_code"]
          set_addon_table_content(addon["name"])
        end
      end
    end

    def add_addon
      ret = display_addon_popup
      if ret
        addon = @config.addons.find{|a| a["name"] == ret["name"]}
        if addon
          addon["reg_code"] = ret["reg_code"]
        else
          @config.addons << ret
        end
        set_addon_table_content(ret["name"])
      end
    end

    def select_addons
      header = Header(
        _("Identifier"),
        _("Version"),
        _("Architecture"),
        _("Release Type"),
        _("Registration Code")
      )
      contents = VBox(
        Table(Id(:addons_table), header, []),
        HBox(
          PushButton(Id(:add), Label.AddButton),
          PushButton(Id(:edit), Label.EditButton),
          PushButton(Id(:delete), Label.DeleteButton),
          HSpacing(0.5),
          # button label
          PushButton(Id(:download),  _("Download Available Extensions...")
          ),
        )
      )
      # help text
      help_text = _("<p>Here you can select which extensions or modules"\
          "will be registered together with the base product.</p>")
      Wizard.SetContents(_("Register Optional Extensions or Modules"), contents, help_text, true, true)
      Wizard.SetNextButton(:next, Label.OKButton)
      set_addon_table_content

      # disable download on a non-registered system
      UI.ChangeWidget(Id(:download), :Enabled, ::Registration::Registration.is_registered?)

      begin
        ret = UI.UserInput
        log.info "ret: #{ret}"

        case ret
        when :add
          add_addon
        when :edit
          edit_addon
        when :delete
          delete_addon
        when :abort, :cancel
          break if Popup.ReallyAbort(true)
        end
      end until [ :next, :back, :download ].include?(ret)

      ret
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
      # TODO store the data
      return :next if ::Registration::Addon.selected.all?(&:free)

      known_reg_codes = {}
      ret = ::Registration::UI::AddonRegCodesDialog.run(::Registration::Addon.selected,
        known_reg_codes)

      # TODO store the data
      log.info "known_reg_codes: #{known_reg_codes}"

      ret
    end

    def refresh_widget_state
      enabled = UI.QueryWidget(Id(:do_registration), :Value)
      all_widgets = [ :reg_server_cert, :email, :reg_code, :slp_discovery,
        :install_updates, :addons, :reg_server_cert_fingerprint_type,
        :reg_server_cert_fingerprint ]

      all_widgets.each do |w|
        UI.ChangeWidget(Id(w), :Enabled, enabled)
      end

      slp_enabled = UI.QueryWidget(Id(:slp_discovery), :Value)
      UI.ChangeWidget(Id(:reg_server), :Enabled, !slp_enabled && enabled)

      fingeprint_enabled = UI.QueryWidget(Id(:reg_server_cert_fingerprint_type), :Value) != :none
      UI.ChangeWidget(Id(:reg_server_cert_fingerprint), :Enabled, fingeprint_enabled && enabled)
    end

    def configure_registration
      caption = _("Product Registration")
      help_text = "<p><b>#{caption}</b></p>"
      help_text += _(
        "<p>Product registration includes your product in SUSE Customer Center database,\n"+
          "enabling you to get online updates and technical support.\n"+
          "To register while installing automatically, select <b>Run Product Registration</b>.</p>"
      )
      help_text += _(
        "<p>If your network deploys a custom registration server, set the correct URL of the server\n" +
          "and the location of the SMT certificate in <b>SMT Server Settings</b>. Refer\n" +
          "to your SMT manual for further assistance.</p>"
      )

      regsettings = VBox(
        Left(
          CheckBox(Id(:do_registration), Opt(:notify), _("Register the Product"),
            @config.do_registration)
        )
      )

      reg_code_settings = VBox(
        # Translators: Text for UI Label - capitalized
        Frame(_("Registration"),
          VBox(
            MinWidth(32, InputField(Id(:email), _("&E-mail Address"), @config.email)),
            VSpacing(0.4),
            MinWidth(32, InputField(Id(:reg_code), _("Registration &Code"),
                @config.reg_code)),
            VSpacing(0.4),
            Left(CheckBox(Id(:install_updates),
                _("Install Available Updates from Update Repositories"),
                @config.install_updates))
          )
        )
      )

      server_settings = VBox(
        # Translators: Text for UI Label - capitalized
        Frame(_("Server Settings"),
          VBox(
            VSpacing(0.2),
            Left(CheckBox(Id(:slp_discovery), Opt(:notify),
                _("Find Registration Server Using SLP Discovery"),
                @config.slp_discovery)),
            VSpacing(0.4),
            # Translators: Text for UI Label - capitalized
            InputField(Id(:reg_server), Opt(:hstretch),
              _("Use Specific Server URL Instead of the Default"),
              @config.reg_server),
            VSpacing(0.4),
            # Translators: Text for UI Label - capitalized
            InputField(
              Id(:reg_server_cert),
              Opt(:hstretch),
              _("Optional SSL Server Certificate URL"),
              @config.reg_server_cert
            ),
            VSpacing(0.4),
            Left(
              ComboBox(
                Id(:reg_server_cert_fingerprint_type),
                Opt(:notify),
                # Translators: Text for UI Label - capitalized
                _("Optional SSL Server Certificate Fingerprint"),
                [
                  Item(Id(:none), _("none"),
                    @config.reg_server_cert_fingerprint_type != "SHA1" &&
                      @config.reg_server_cert_fingerprint_type != "SHA256"),
                  Item(Id("SHA1"), "SHA1", @config.reg_server_cert_fingerprint_type == "SHA1"),
                  Item(Id("SHA256"), "SHA256", @config.reg_server_cert_fingerprint_type == "SHA256")
                ]
              )
            ),
            InputField(
              Id(:reg_server_cert_fingerprint),
              Opt(:hstretch),
              # Translators: Text for UI Label - capitalized
              _("SSL Certificate Fingerprint"),
              @config.reg_server_cert_fingerprint
            )
          )
        )
      )

      contents = VBox(
        VSpacing(1),
        regsettings,
        HBox(
          HSpacing(2),
          VBox(
            VSpacing(1),
            reg_code_settings,
            VSpacing(1),
            server_settings,
            VSpacing(0.4),
            PushButton(Id(:addons), _("Register Extensions or Modules...")),
            VSpacing(0.4)
          )
        )
      )

      Wizard.CreateDialog
      Wizard.SetContents(caption, contents, help_text, false, true)
      Wizard.SetNextButton(:next, Label.FinishButton)

      refresh_widget_state

      begin
        ret = UI.UserInput
        log.info "ret: #{ret}"

        case ret
        when :do_registration, :slp_discovery, :reg_server_cert_fingerprint_type
          refresh_widget_state
        when :abort, :cancel
          break if Popup.ReallyAbort(true)
        when :next
          # TODO FIXME: input validation
        end
      end until ret == :next || ret == :back || ret == :addons

      if ret == :next || ret == :addons
        data_widgets = [ :do_registration, :reg_server, :reg_server_cert,
          :email, :reg_code, :slp_discovery, :install_updates
        ]

        data = data_widgets.map do |w|
          [w.to_s, UI.QueryWidget(Id(w), :Value)]
        end

        import_data = Hash[data]
        # keep the current addons
        import_data["addons"] = @config.addons
        @config.import(import_data)
      end

      ret
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
