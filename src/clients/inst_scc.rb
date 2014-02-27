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

require "registration/exceptions"
require "registration/helpers"

module Yast
  class InstSccClient < Client
    include Yast::Logger

    def main
      Yast.import "UI"

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
          rescue Registration::ServiceError => e
            log.error("Service error: #{e.message % e.service}")
            Report.Error(_(e.message) % e.service)
          rescue Registration::PkgError => e
            log.error("Pkg error: #{e.message}")
            Report.Error(_(e.message))
          rescue Exception => e
            log.error("SCC registration failed: #{e}, #{e.backtrace}")
            Report.Error(_("Registration failed."))
          end
        end

        return :next if ret == :skip && confirm_skipping
      end

      return ret
    end


    private

    def register(email, reg_code)
      scc = SccApi::Connection.new(email, reg_code)

      # set the current language to receive translated error messages
      scc.language = Registration::Helpers.language

      # announce (register the system) first
      credentials = run_with_feedback(_("Registering the System..."), _("Contacting the SUSE Customer Center server")) do
        scc.announce
      end

      # ensure the zypp config directories are writable in inst-sys
      Registration::SwMgmt.zypp_config_writable!

      # write the global credentials
      credentials.write

      # then register the product(s)
      product_services = run_with_feedback(_("Registering the Product..."), _("Contacting the SUSE Customer Center server")) do
        # there will be just one base product, but theoretically there can be more...
        Registration::SwMgmt.products_to_register.map do |base_product|
          log.info("Registering base product: #{base_product.inspect}")
          scc.register(base_product)
        end
      end

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
          Registration::SwMgmt.add_services(product_services, credentials)
        ensure
          Progress.Finish
        end
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

    def run_with_feedback(header, label, &block)
      Popup.ShowFeedback(header, label)
      yield
    ensure
      Popup.ClearFeedback
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

  end
end

Yast::InstSccClient.new.main
