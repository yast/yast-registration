# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2014 Novell, Inc. All Rights Reserved.
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
#

require "yast"
require "suse/connect"

require "registration/helpers"
require "registration/exceptions"

module Registration

  class SccHelpers
    include Yast::Logger
    extend Yast::I18n

    textdomain "registration"

    Yast.import "Mode"
    Yast.import "Popup"
    Yast.import "Report"

    def self.catch_registration_errors(&block)
      begin
        yield
        true
      rescue SocketError
        # Error popup
        if Yast::Mode.installation
          if Yast::Popup.YesNo(
              _("Network is not configured, the registration server cannot be reached.\n" +
                  "Do you want to configure the network now?"))

            ::Registration::Helpers::run_network_configuration
          end
        else
          Yast::Report.Error(_("Network error, check the network configuration."))
        end
        false
      rescue Timeout::Error
        # Error popup
        Yast::Report.Error(_("Connection time out."))
        false
      rescue SUSE::Connect::ApiError => e
        log.error "Received error: #{e.code}: #{e.body}"
        case e.response
        when Net::HTTPUnauthorized, Net::HTTPUnprocessableEntity
          # Error popup
          report_error(_("The email address is not known or\nthe registration code is not valid."), e)
        when Net::HTTPClientError
          report_error(_("Registration client error."), e)
        when Net::HTTPServerError
          report_error(_("Registration server error.\nRetry registration later."), e)
        else
          report_error(_("Registration failed."), e)
        end
        false
      rescue ::Registration::ServiceError => e
        log.error("Service error: #{e.message % e.service}")
        Yast::Report.Error(_(e.message) % e.service)
        false
      rescue ::Registration::PkgError => e
        log.error("Pkg error: #{e.message}")
        Yast::Report.Error(_(e.message))
        false
      rescue Exception => e
        log.error("SCC registration failed: #{e}, #{e.backtrace}")
        Yast::Report.Error(_("Registration failed."))
        false
      end
    end

    private

    def self.report_error(msg, api_error)
      localized_error = api_error.body["localized_error"] || ""

      if !localized_error.empty?
        # %s are error details
        localized_error = ("\n\n" + _("Details: %s") % localized_error)
      end

      Yast::Report.Error(msg + localized_error)
    end

  end
end
