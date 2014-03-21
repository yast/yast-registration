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

require "registration/storage"

module Yast
  class SccAutoClient < Client
    include Yast::Logger

    def main
      Yast.import "UI"

      textdomain "registration"

      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Report"
      Yast.import "Summary"
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
        ret = false
      end

      log.info "ret: #{ret}"
      log.info "scc_auto finished"

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


    # Create a textual summary and a list of unconfigured cards
    # return summary of the current configuration
    def summary
      summary = ""

      # Translators: Heading - capitalized
      summary = Summary.AddHeader(summary, _("Product Registration"))

      summary = Summary.OpenList(summary)
      summary = Summary.AddListItem(summary,
        @config.do_registration ?
          _("Run registration during autoinstallation") :
          _("Skip registration during autoinstallation")
      )
      summary = Summary.CloseList(summary)

      if @config.do_registration
        summary = Summary.AddHeader(summary, _("Registration Settings"))
        summary = Summary.OpenList(summary)
        summary = Summary.AddListItem(summary, _("Email: %s") % @config.email)

        if @config.reg_key && !@config.reg_key.empty?
          summary = Summary.AddListItem(summary, _("Registration Key: <em>Configured</em>"))
        end

        if @config.install_updates
          summary = Summary.AddListItem(summary, _("Install Available Patches"))
        end

        summary = Summary.CloseList(summary)

        if (@config.reg_server && !@config.reg_server.empty?) || (@config.slp_discovery)
          summary = Summary.AddHeader(summary, _("Registration Server Settings"))
          summary = Summary.OpenList(summary)

          if !@config.reg_server.empty?
            summary = Summary.AddListItem(summary, (_("Server URL: %s") % @config.reg_server))
          end

          if @config.slp_discovery
            summary = Summary.AddListItem(summary, _("Server URL: %s") % _("Use SLP discovery"))
          end

          if @config.reg_server_cert && !@config.reg_server.empty?
            summary = Summary.AddListItem(
              summary,
              _("Server Certificate: %s") % @config.reg_server_cert
            )
          end
          summary = Summary.CloseList(summary)
        end

        if !@config.addons.empty?
          summary = Summary.AddHeader(summary, _("Addon Products"))
          summary = Summary.OpenList(summary)

          @config.addons.each do |addon|
            summary = Summary.AddListItem(summary, addon["name"])
          end
          summary = Summary.CloseList(summary)
        end
      end

      summary
    end

    # Write all settings
    # return true on success
    def write
      Report.Error("Write not implemented yet")
    end

    def auto_packages
      ret = { "install" => [], "remove" => [] }
      log.info "Registration needs these packages: #{ret}"
      ret
    end

    # ---------------------------------------------------------

    def set_addon_table_content(current = nil)
      content = @config.addons.map do |a|
        Item(Id(a["name"]), a["name"], a["reg_key"])
      end

      UI.ChangeWidget(Id(:addons_table), :Items, content)
      UI.ChangeWidget(Id(:addons_table), :CurrentItem, current) if current
    end

    def display_addon_popup(name = "", reg_key = "")
      content = VBox(
        InputField(Id(:name), _("Add-on &Name"), name),
        InputField(Id(:reg_key), _("Registration &Key"), reg_key),
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
            "reg_key" => UI.QueryWidget(Id(:reg_key), :Value)
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
      if selected
        if Popup.YesNo(_("Really delete add-on '%s'?") % selected)
          @config.addons.reject!{|a| a["name"] == selected}
          set_addon_table_content
        end
      end
    end

    def edit_addon
      selected = UI.QueryWidget(Id(:addons_table), :CurrentItem)
      if selected
        addon = @config.addons.find{|a| a["name"] == selected}

        ret = display_addon_popup(selected, addon["reg_key"])
        if ret
          addon["name"] = ret["name"]
          addon["reg_key"] = ret["reg_key"]
          set_addon_table_content(addon["name"])
        end
      end
    end

    def add_addon
      ret = display_addon_popup
      if ret
        addon = @config.addons.find{|a| a["name"] == ret["name"]}
        if addon
          addon["reg_key"] = ret["reg_key"]
        else
          @config.addons << ret
        end
        set_addon_table_content(ret["name"])
      end
    end

    def select_addons
      header = Header(_("Name"), _("Registration key"))
      contents = VBox(
        Table(Id(:addons_table), header, []),
        HBox(
          PushButton(Id(:add), Label.AddButton),
          PushButton(Id(:edit), Label.EditButton),
          PushButton(Id(:delete), Label.DeleteButton)
        )
      )
      help_text = ""
      Wizard.SetContents(_("Register Optional Add-ons"), contents, help_text, true, true)
      Wizard.SetNextButton(:next, Label.OKButton)
      set_addon_table_content

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
      end until ret == :next || ret == :back || ret == :addons

      ret
    end

    def disable_widgets
      enabled = UI.QueryWidget(Id(:do_registration), :Value)
      all_widgets = [ :reg_server_cert, :email, :reg_key, :slp_discovery,
        :install_updates, :addons ]

      all_widgets.each do |w|
        UI.ChangeWidget(Id(w), :Enabled, enabled)
      end

      slp_enabled = UI.QueryWidget(Id(:slp_discovery), :Value)
      UI.ChangeWidget(Id(:reg_server), :Enabled, !slp_enabled && enabled)
    end

    def configure_registration
      caption = _("Product Registration")
      help_text = "<p><b>#{caption}</b></p>"
      help_text << _(
        "<p>Product registration includes your product in SUSE Customer Center database, enabling you to get online updates and technical support. To register while installing automatically, select <b>Run Product Registration</b>.</p>"
      )
      help_text << _(
        "<p>If your network deploys a custom registration server, set the correct URL of the server\n" +
          "and the location of the SMT certificate in <b>SMT Server Settings</b>. Refer\n" +
          "to your SMT manual for further assistance.</p>"
      )

      regsettings = VBox(
        Left(
          CheckBox(Id(:do_registration), Opt(:notify), _("Register the Product"), @config.do_registration)
        )
      )

      reg_key_settings = VBox(
        # Translators: Text for UI Label - capitalized
        Frame(_("Registration"),
          VBox(
            MinWidth(32, InputField(Id(:email), _("&Email"), @config.email)),
            VSpacing(0.4),
            MinWidth(32, InputField(Id(:reg_key), _("Registration &Code"), @config.reg_key)),
            VSpacing(0.4),
            Left(CheckBox(Id(:install_updates), _("Install Available Patches from Update Repositories"), @config.install_updates))
          )
        )
      )

      server_settings = VBox(
        # Translators: Text for UI Label - capitalized
        Frame(_("Server Settings"),
          VBox(
            VSpacing(0.2),
            Left(CheckBox(Id(:slp_discovery), Opt(:notify), _("Find Registration Server Using SLP Discovery"), @config.slp_discovery)),
            VSpacing(0.4),
            # Translators: Text for UI Label - capitalized
            InputField(Id(:reg_server), Opt(:hstretch), _("Use Specific Server URL Instead of the Default"), @config.reg_server),
            VSpacing(0.4),
            # Translators: Text for UI Label - capitalized
            InputField(
              Id(:reg_server_cert),
              Opt(:hstretch),
              _("Optional Server Certificate"),
              @config.reg_server_cert
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
            reg_key_settings,
            VSpacing(1),
            server_settings,
            VSpacing(0.4),
            PushButton(Id(:addons), _("Register Add-ons...")),
            VSpacing(0.4)
          )
        )
      )

      Wizard.CreateDialog
      Wizard.SetContents(caption, contents, help_text, false, true)
      Wizard.SetNextButton(:next, Label.FinishButton)

      disable_widgets

      begin
        ret = UI.UserInput
        log.info "ret: #{ret}"

        case ret
        when :do_registration, :slp_discovery
          disable_widgets
        when :abort, :cancel
          break if Popup.ReallyAbort(true)
        when :next
          #          smtServer = Convert.to_string(UI.QueryWidget(Id(:smturl), :Value))
          #          smtServerCert = Convert.to_string(
          #            UI.QueryWidget(Id(:smtcert), :Value)
          #          )
          #
          #          if !Builtins.regexpmatch(smtServer, "^https://.+") && smtServer != "" ||
          #              smtServer == "" && smtServerCert != ""
          #            Popup.Message(_("SMT Server URL must start with https://"))
          #            ret = nil
          #          end
          #
          #          if !Builtins.regexpmatch(smtServerCert, "^(https?|ftp)://.+") &&
          #              !Builtins.regexpmatch(smtServerCert, "^floppy/.+") &&
          #              !Builtins.regexpmatch(smtServerCert, "^/.+") &&
          #              !Builtins.regexpmatch(smtServerCert, "^(ask|done)$") &&
          #              smtServerCert != ""
          #            Popup.Message(
          #              _(
          #                "Location of SMT Certificate invalid.\nSee your SMT documentation.\n"
          #              )
          #            )
          #            ret = nil
          #          end
        end
      end until ret == :next || ret == :back || ret == :addons

      if ret == :next || ret == :addons
        data_widgets = [ :do_registration, :reg_server, :reg_server_cert,
          :email, :reg_key, :slp_discovery, :install_updates
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

    # UI workflow definition
    def start_workflow
      aliases = {
        "general"  => lambda { configure_registration() },
        "addons"   => [ lambda { select_addons() }, true ]
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
          :next    => "general"
        }
      }

      log.info "Starting scc_auto sequence"
      Sequencer.Run(aliases, sequence)
    end

  end
end

Yast::SccAutoClient.new.main
