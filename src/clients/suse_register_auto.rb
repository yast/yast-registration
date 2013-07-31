# encoding: utf-8

# ***************************************************************************
#
# Copyright (c) 2006 - 2012 Novell, Inc.
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
# File:        suse_register_auto
# Module:      Installation
# Summary:     Configure Product Registration for Autoinstallation
# Authors:     J. Daniel Schmidt <jdsn@suse.de>
#
# Configure Product Registration for Autoinstallation
#
# $Id: suse_register_auto.ycp 1 2006-03-27 13:20:02Z jdsn $
module Yast
  class SuseRegisterAutoClient < Client
    def main
      Yast.import "UI"

      textdomain "registration"

      Yast.import "Register"
      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Summary"
      Yast.import "Popup"
      Yast.import "String"



      #---------------------------------------------------------------------------
      # MAIN
      #---------------------------------------------------------------------------
      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("suse_register_auto started")


      @ret = nil
      @func = ""
      @param = {}

      # Check arguments
      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          Ops.is_string?(WFM.Args(0))
        @func = Convert.to_string(WFM.Args(0))
        if Ops.greater_than(Builtins.size(WFM.Args), 1) &&
            Ops.is_map?(WFM.Args(1))
          @param = Convert.to_map(WFM.Args(1))
        end
      end

      Builtins.y2milestone("func=%1", @func)
      Builtins.y2milestone("param=%1", @param)

      # Create a summary
      if @func == "Summary"
        @ret = Summary()
      # Reset configuration
      elsif @func == "Reset"
        Import({})
        @ret = {}
      # Change configuration (run AutoSequence)
      elsif @func == "Change"
        @ret = suse_register_configuration
      # Import configuration
      elsif @func == "Import"
        @ret = Import(@param)
      # Return actual state
      elsif @func == "Export"
        @ret = Export()
      # Return needed packages
      elsif @func == "Packages"
        @ret = AutoPackages()
      # Write given settings
      elsif @func == "Write"
        Yast.import "Progress"
        Progress.off
        @ret = Write()
        Progress.on
      elsif @func == "GetModified"
        @ret = Register.autoYaSTModified
      elsif @func == "SetModified"
        Register.autoYaSTModified = true
      else
        Builtins.y2error("Unknown function: %1", @func)
        @ret = false
      end

      Builtins.y2milestone("ret=%1", @ret)
      Builtins.y2milestone("suse_register_auto finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret) 

      # EOF
    end

    # Get all settings from the first parameter
    # (For use by autoinstallation.)
    # @param [Hash] settings The YCP structure to be imported.
    # @return [Boolean] True on success
    def Import(settings)
      settings = deep_copy(settings)
      Builtins.y2debug("Import called, settings: %1", settings)
      Register.Import(settings)
    end


    # Export the settings to a single map
    # (For use by autoinstallation.)

    def Export
      Builtins.y2debug("Export called")
      Register.Export
    end


    # Create a textual summary and a list of unconfigured cards
    # @return summary of the current configuration
    def Summary
      #Register::do_registration=false;
      #Register::submit_optional=true;
      #Register::submit_hwdata=true;
      summary = ""

      # Translators: Heading - capitalized
      summary = Summary.AddHeader(summary, _("Product Registration"))
      # Translators: Text in a sentece-like environment  - normal capitalization
      summary = Summary.AddLine(
        summary,
        Register.do_registration ?
          _("Run during autoinstallation") :
          _("Do not run during autoinstallation")
      )

      items_count = Builtins.size(Register.registration_data)
      # Translators: Sentence-like text for singular and plural (incl. zero) of items
      items_msg = _("%1 item of registration data")
      items_msg = Builtins.sformat(items_msg, items_count) # (bnc#184893)

      if Register.do_registration
        summary = Summary.AddHeader(summary, _("Included Information"))
        summary = Summary.OpenList(summary)
        # Translators: Text in a sentece-like environment  - normal capitalization
        summary = Summary.AddListItem(
          summary,
          Register.submit_hwdata ? _("Hardware profile") : ""
        )
        # Translators: Text in a sentece-like environment  - normal capitalization
        summary = Summary.AddListItem(
          summary,
          Register.submit_optional ? _("Optional information") : ""
        )
        summary = Summary.AddListItem(summary, items_msg)
        summary = Summary.CloseList(summary)
      end

      if Register.smt_server != ""
        summary = Summary.AddHeader(summary, _("SMT Server Settings"))
        summary = Summary.OpenList(summary)
        summary = Summary.AddListItem(
          summary,
          Builtins.sformat(_("SMT Server: %1"), Register.smt_server)
        )
        if Register.smt_server_cert != ""
          summary = Summary.AddListItem(
            summary,
            Builtins.sformat(_("SMT Certificate: %1"), Register.smt_server_cert)
          )
        end
        summary = Summary.CloseList(summary)
      end

      summary
    end

    # Write all settings
    # @return true on success
    def Write
      Register.Write
    end


    def Read
      Register.Read

      nil
    end

    def AutoPackages
      retmap = { "install" => [], "remove" => [] }

      xenType = nil
      xenType = Register.xenType

      if xenType == :xen0
        Ops.set(
          retmap,
          "install",
          Builtins.add(Ops.get_list(retmap, "install", []), "xen-tools")
        )
      elsif xenType == :xenU
        Ops.set(
          retmap,
          "remove",
          Builtins.add(Ops.get_list(retmap, "remove", []), "xen-tools")
        )
        Ops.set(
          retmap,
          "install",
          Builtins.add(Ops.get_list(retmap, "install", []), "xen-tools-domU")
        )
      else
        Builtins.y2milestone(
          "XEN is disabled or could not be detected. No package changes will be applied."
        )
      end

      Builtins.y2milestone(
        "Registration suggests the following package changes: %1",
        retmap
      )
      deep_copy(retmap)
    end



    # ---------------------------------------------------------


    # Host edit dialog
    # @param [Fixnum] id id of the edited host
    # @param [Yast::Term] entry edited entry
    # @param forbidden already used IP addresses
    # @return host or nil, if canceled
    def KeyValueDialog(id, entry)
      entry = deep_copy(entry)
      Builtins.y2debug("KeyValueDialog: id: %1", id)
      Builtins.y2debug("KeyValueDialog: entry: %1", entry)

      UI.OpenDialog(
        Opt(:decorated),
        VBox(
          HSpacing(1),
          VBox(
            # TextEntry label
            TextEntry(Id(:key), _("&Key"), Ops.get_string(entry, 1, "")),
            # TextEntry label
            TextEntry(Id(:value), _("&Value"), Ops.get_string(entry, 2, ""))
          ),
          HSpacing(1),
          ButtonBox(
            PushButton(Id(:ok), Opt(:default), Label.OKButton),
            PushButton(Id(:cancel), Label.CancelButton)
          )
        )
      )

      if entry == term(:empty)
        UI.SetFocus(Id(:key))
      else
        UI.SetFocus(Id(:value))
      end

      ret = nil
      newentry = nil
      begin
        ret = UI.UserInput
        break if ret != :ok

        key = Convert.to_string(UI.QueryWidget(Id(:key), :Value))
        value = Convert.to_string(UI.QueryWidget(Id(:value), :Value))
        key = String.CutRegexMatch(key, "[^A-Za-z0-9_-]+", true)
        if key == ""
          Popup.Notify(_("Key is invalid."))
          UI.ChangeWidget(Id(:key), :Value, key)
          ret = nil
        end
        newentry = Item(Id(id), key, value)
      end until ret == :ok || ret == :cancel

      UI.CloseDialog
      return nil if ret != :ok
      deep_copy(newentry)
    end

    # ---------------------------------------------------------
    # ---------------------------------------------------------


    def suse_register_configuration
      caption = _("Product Registration")
      help_text_caption = Builtins.sformat("<p><b>%1</b></p>", caption)
      help_text_para1 = _(
        "<p>Product registration includes your product in Novell's database, enabling you to get online updates and technical support. To register while installing automatically, select <b>Run Product Registration</b>. To simplify the procedure, include information from your system with <b>Hardware Profile</b> and <b>Optional Information</b>.</p>"
      )
      help_text_para2 = _(
        "<p>Get more information about the registration process with <tt>suse_register -h</tt>.</p>"
      )
      help_text_para3 = _(
        "<p>Other information used for registration is shown in <b>Registration\n" +
          "Data</b>.<br>To add a new key and value pair, press <b>Add</b> then enter the\n" +
          "appropriate values. These parameters are the ones that can be passed with <tt>suse_register\n" +
          "-a</tt>.<br>Get more information with <tt>suse_register -p</tt>. Remove a\n" +
          "key-value pair with <b>Delete</b> or modify an existing pair with <b>Edit</b>.</p>"
      )

      help_text_para4 = _(
        "<p>If your network deploys a custom SMT server, set the URL of the SMT Server\n" +
          "and the location of the SMT certificate in <b>SMT Server Settings</b>. Refer\n" +
          "to your SMT manual for further assistance.</p>"
      )


      help_text = Ops.add(
        Ops.add(
          Ops.add(Ops.add(help_text_caption, help_text_para1), help_text_para2),
          help_text_para3
        ),
        help_text_para4
      )

      smtsettings = VBox(
        # Translators: Text for UI Label - capitalized
        Left(Label(_("SMT Server Settings"))),
        # Translators: Text for UI Label - capitalized
        TextEntry(Id(:smturl), Opt(:hstretch, :notify), _("SMT Server"), ""),
        # Translators: Text for UI Label - capitalized
        TextEntry(
          Id(:smtcert),
          Opt(:hstretch, :notify),
          _("SMT Certificate"),
          ""
        )
      )

      regsettings = VBox(
        Left(
          CheckBox(Id(:run), Opt(:notify), _("Run Product Registration"), false)
        ),
        HBox(
          HSpacing(3.0),
          VBox(
            # Translators: Text for UI Label - capitalized
            Left(Label(_("Include in Registration"))),
            # Translators: Text for UI Label - capitalized
            Left(
              CheckBox(Id(:sub_hw), Opt(:notify), _("Hardware Profile"), false)
            ),
            # Translators: Text for UI Label - capitalized
            Left(
              CheckBox(
                Id(:sub_opt),
                Opt(:notify),
                _("Optional Information"),
                false
              )
            )
          )
        ),
        VSpacing(1)
      )


      contents = VBox(
        HBox(regsettings, smtsettings),
        VBox(
          VSpacing(0.5),
          # Translators: Text for UI Label - capitalized
          Left(Label(_("Registration Data to Use"))),
          MinSize(
            10,
            5,
            Table(
              Id(:table),
              Opt(:notify, :vstretch),
              Header(_("Key"), _("Value")),
              []
            )
          ),
          HBox(
            PushButton(Id(:add), _("Ad&d")),
            PushButton(Id(:edit), Opt(:disabled), _("&Edit")),
            PushButton(Id(:delete), Opt(:disabled), _("De&lete"))
          ),
          VSpacing(0.5)
        )
      )


      Wizard.CreateDialog
      Wizard.SetContents(caption, contents, help_text, false, true)
      Wizard.SetNextButton(:next, Label.FinishButton)

      table_items = []
      mycount = 0
      # restore table items
      Builtins.foreach(Register.registration_data) do |key, value|
        table_items = Builtins.add(table_items, Item(Id(mycount), key, value))
        mycount = Ops.add(mycount, 1)
      end

      # get current changes
      UI.ChangeWidget(Id(:table), :Items, table_items)
      UI.ChangeWidget(Id(:run), :Value, Register.do_registration)
      UI.ChangeWidget(Id(:sub_hw), :Value, Register.submit_hwdata)
      UI.ChangeWidget(Id(:sub_opt), :Value, Register.submit_optional)
      UI.ChangeWidget(Id(:smturl), :Value, Register.smt_server)
      UI.ChangeWidget(Id(:smtcert), :Value, Register.smt_server_cert)
      items = Builtins.size(table_items)
      UI.ChangeWidget(Id(:edit), :Enabled, Ops.greater_than(items, 0))
      UI.ChangeWidget(Id(:delete), :Enabled, Ops.greater_than(items, 0))

      ret = nil
      begin
        ret = Convert.to_symbol(UI.UserInput)

        if ret == :run || ret == :sub_hw || ret == :sub_opt
          Register.do_registration = Convert.to_boolean(
            UI.QueryWidget(Id(:run), :Value)
          )
          Register.submit_hwdata = Convert.to_boolean(
            UI.QueryWidget(Id(:sub_hw), :Value)
          )
          Register.submit_optional = Convert.to_boolean(
            UI.QueryWidget(Id(:sub_opt), :Value)
          )

          Builtins.y2debug("do_registration: %1", Register.do_registration)
          Builtins.y2debug("submit_hwdata: %1", Register.submit_hwdata)
          Builtins.y2debug("submit_optional: %1", Register.submit_optional)
        elsif ret == :edit || ret == :table
          cur = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
          cur_item = Builtins.filter(table_items) do |e|
            cur == Ops.get(e, [0, 0])
          end

          newitem = KeyValueDialog(cur, Ops.get(cur_item, 0))
          if newitem == nil
            next
          else
            table_items = Builtins.maplist(table_items) do |e|
              next deep_copy(newitem) if cur == Ops.get_integer(e, [0, 0], -1)
              deep_copy(e)
            end
          end

          UI.ChangeWidget(Id(:table), :Items, table_items)
          UI.ChangeWidget(Id(:table), :CurrentItem, cur)

          Builtins.y2debug("cur: %1", cur)
          Builtins.y2debug("cur_item: %1", cur_item)
        elsif ret == :add
          newid = Ops.add(items, 1)
          newitem = KeyValueDialog(newid, term(:empty))
          if newitem == nil
            next
          else
            table_items = Builtins.add(table_items, newitem)
            UI.ChangeWidget(Id(:table), :Items, table_items)
            UI.ChangeWidget(Id(:table), :CurrentItem, newid)
          end
          Builtins.y2debug("newitem: %1", newitem)
        elsif ret == :delete
          cur = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))

          table_items = Builtins.filter(table_items) do |e|
            next false if cur == Ops.get(e, [0, 0])
            true
          end

          Builtins.y2debug("deleted from list item: %1", cur)
          UI.ChangeWidget(Id(:table), :Items, table_items)
          UI.ChangeWidget(Id(:table), :CurrentItem, Ops.subtract(cur, 1))
        elsif ret == :abort || ret == :cancel
          if Popup.ReallyAbort(true)
            break
          else
            next
          end
        elsif ret == :next
          smtServer = Convert.to_string(UI.QueryWidget(Id(:smturl), :Value))
          smtServerCert = Convert.to_string(
            UI.QueryWidget(Id(:smtcert), :Value)
          )

          if !Builtins.regexpmatch(smtServer, "^https://.+") && smtServer != "" ||
              smtServer == "" && smtServerCert != ""
            Popup.Message(_("SMT Server URL must start with https://"))
            ret = nil
          end

          if !Builtins.regexpmatch(smtServerCert, "^(https?|ftp)://.+") &&
              !Builtins.regexpmatch(smtServerCert, "^floppy/.+") &&
              !Builtins.regexpmatch(smtServerCert, "^/.+") &&
              !Builtins.regexpmatch(smtServerCert, "^(ask|done)$") &&
              smtServerCert != ""
            Popup.Message(
              _(
                "Location of SMT Certificate invalid.\nSee your SMT documentation.\n"
              )
            )
            ret = nil
          end
          Register.smt_server = smtServer
          Register.smt_server_cert = smtServerCert
        end

        # refresh counter and buttons
        items = Builtins.size(table_items)
        UI.ChangeWidget(Id(:edit), :Enabled, Ops.greater_than(items, 0))
        UI.ChangeWidget(Id(:delete), :Enabled, Ops.greater_than(items, 0))
      end until ret == :next || ret == :abort || ret == :back


      if ret == :next
        Register.do_registration = Convert.to_boolean(
          UI.QueryWidget(Id(:run), :Value)
        )
        Register.submit_hwdata = Convert.to_boolean(
          UI.QueryWidget(Id(:sub_hw), :Value)
        )
        Register.submit_optional = Convert.to_boolean(
          UI.QueryWidget(Id(:sub_opt), :Value)
        )

        Register.registration_data = {}
        Builtins.foreach(table_items) do |e|
          Ops.set(
            Register.registration_data,
            Ops.get_string(e, 1, ""),
            Ops.get_string(e, 2, "")
          )
        end

        Builtins.y2debug("finish: wrote settings to global variables")
        Builtins.y2debug("do_registration: %1", Register.do_registration)
        Builtins.y2debug("submit_hwdata: %1", Register.submit_hwdata)
        Builtins.y2debug("submit_optional: %1", Register.submit_optional)
        Builtins.y2debug("registration_data: %1", Register.registration_data)
        Builtins.y2debug("smt_server: %1", Register.smt_server)
        Builtins.y2debug("smt_server_cert: %1", Register.smt_server_cert)
      end

      UI.CloseDialog

      ret
    end
  end
end

Yast::SuseRegisterAutoClient.new.main
