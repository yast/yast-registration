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
require "scc_api"

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
      rescue SccApi::NoNetworkError
        # Error popup
        if Yast::Mode.installation && Yast::Popup.YesNo(
            _("Network is not configured, the registration server cannot be reached.\n" +
                "Do you want to configure the network now?") )
          Registration::Helpers::run_network_configuration
        end
        false
      rescue SccApi::NotAuthorized
        # Error popup
        Yast::Report.Error(_("The email address is not known or\nthe registration code is not valid."))
        false
      rescue Timeout::Error
        # Error popup
        Yast::Report.Error(_("Connection time out."))
        false
      rescue SccApi::ErrorResponse => e
        # TODO FIXME: display error details from the response
        Yast::Report.Error(_("Registration server error.\n\nRetry registration later."))
        false
      rescue SccApi::HttpError => e
        case e.response
        when Net::HTTPClientError
          Yast::Report.Error(_("Registration client error."))
        when Net::HTTPServerError
          Yast::Report.Error(_("Registration server error.\n\nRetry registration later."))
        else
          Yast::Report.Error(_("Registration failed."))
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

  end
end
