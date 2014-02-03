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

module Yast
  class InstSccClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "registration"

      Yast.import "Popup"
      Yast.import "GetInstArgs"
      Yast.import "Wizard"
      Yast.import "Report"
      Yast.import "Mode"

      # redirect the scc_api log to y2log
      SccApi::GlobalLogger.instance.log = Y2Logger.instance

      show_scc_credentials_dialog

      ret = nil

      continue_buttons = [:next, :back, :close, :abort]
      while !continue_buttons.include?(ret) do
        ret = UI.UserInput

        if ret == :next
          email = UI.QueryWidget(:email, :Value)
          reg_code = UI.QueryWidget(:reg_code, :Value)

          begin
            register(email, reg_code)
          rescue Exception => e
            Builtins.y2error("SCC registration failed: #{e}, #{e.backtrace}")
            # TODO: display error details
            Report.Error(_("Registration failed."))
            ret = nil
          end
        end

        # skip the registration
        return :next if ret == :skip
      end

      return ret
    end


    private

    def register(email, reg_code)
      scc = SccApi::Connection.new(email, reg_code)

      # announce (register the system) first
      begin
        Popup.ShowFeedback(_("Registering the System..."), _("Contacting the SUSE Customer Center server"))
        result = scc.announce
      ensure
        Popup.ClearFeedback
      end

      # then register the product(s)
      begin
        Popup.ShowFeedback(_("Registering the Product..."), _("Contacting the SUSE Customer Center server"))

        # there will be just one base product, but theoretically there can be more...
        selected_base_products.each do |base_product|
          Builtins.y2milestone("Registering base product: #{base_product.inspect}")
          result = scc.register(base_product)

          # TODO: remove this
          # Popup.Message("SCC response:\n#{JSON.pretty_generate(result)}")
          Popup.Message("The system has been registered.")
        end
      ensure
        Popup.ClearFeedback
      end
    end

    def scc_credentials_dialog
      VBox(
        Frame(_("SUSE Customer Center Credentials"),
          MarginBox(1, 0.5,
            VBox(
              InputField(Id(:email), _("&Email")),
              VSpacing(0.5),
              InputField(Id(:reg_code), _("Registration &Code"))
            )
          )
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

    def selected_base_products
      # just for debugging: return [{"name" => "SUSE_SLES", "arch" => "x86_64", "version" => "12"}]

      # source 0 is the base installation repo, the repos added later are considered as add-ons
      # although they can also contain a different base product
      selected_base_products = Pkg.ResolvableProperties("", :product, "").find_all do |p|
        p["source"] == 0 && p["status"] == :selected
      end

      # filter out not needed data
      product_info = selected_base_products.map{|p| { "name" => p["name"], "arch" => p["arch"], "version" => p["version"]}}

      Builtins.y2milestone("Found selected base products: #{product_info}")

      product_info
    end

  end
end

Yast::InstSccClient.new.main
