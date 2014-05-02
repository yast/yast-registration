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
require "registration/storage"
require "registration/ui/import_certificate_dialog"

module Registration

  class SccHelpers
    include Yast::Logger
    extend Yast::I18n

    # openSSL error codes for which the import SSL certificate dialog is shown,
    # for the other error codes just the error message is displayed
    # (importing the certificate would not help)
    IMPORT_ERROR_CODES = UI::ImportCertificateDialog::OPENSSL_ERROR_MESSAGES.keys

    # indent size used in error popup
    INDENT = " " * 3

    textdomain "registration"

    Yast.import "Mode"
    Yast.import "Popup"
    Yast.import "Report"

    def self.catch_registration_errors(&block)
      begin
        # reset the previous SSL errors
        Storage::SSLErrors.instance.reset

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
      rescue OpenSSL::SSL::SSLError => e
        log.error "OpenSSL error: #{e}"

        cert = Storage::SSLErrors.instance.ssl_failed_cert
        error_code = Storage::SSLErrors.instance.ssl_error_code

        # in AutoYast mode just report an error without user interaction,
        # otherwise check a certificate present and the error code
        if !Yast::Mode.autoinst && cert && IMPORT_ERROR_CODES.include?(error_code)
          # retry after successfull import
          retry if import_ssl_certificate(cert)
        else
          # try to use a translatable message first, if not found then use
          # the original error message from openSSL
          msg = UI::ImportCertificateDialog::OPENSSL_ERROR_MESSAGES[error_code]
          msg = msg ? _(msg) : Storage::SSLErrors.instance.ssl_error_msg

          Yast::Report.Error(
            error_with_details(_("Secure connection error: %s") % msg, ssl_error_details)
          )
        end

        false
      rescue Exception => e
        log.error("SCC registration failed: #{e}, #{e.backtrace}")
        Yast::Report.Error(_("Registration failed."))
        false
      end
    end

    private

    def self.report_error(msg, api_error)
      localized_error = api_error.body["localized_error"]

      Yast::Report.Error(error_with_details(msg, localized_error))
    end

    def self.error_with_details(error, details)
      return error if (!details || details.empty?)

      # %s are error details
      error + "\n\n" + (_("Details: %s") % details)
    end

    def self.ssl_error_details()
      # label follwed by a certificate description
      details = [ _("Certificate:") ]

      cert = Storage::SSLErrors.instance.ssl_failed_cert
      if cert
        details << _("Issued To")
        details.concat(cert_name_details(cert.subject))
        details << ""
        details << _("Issued By")
        details.concat(cert_name_details(cert.issuer))
        details << ""
        details << _("SHA1 Fingerprint: ")
        details << INDENT + ::SUSE::Connect::SSLCertificate.sha1_fingerprint(cert)
        details << _("SHA256 Fingerprint: ")

        sha256 = ::SUSE::Connect::SSLCertificate.sha256_fingerprint(cert)
        if Yast::UI.TextMode && Yast::UI.GetDisplayInfo["Width"] < 105
          # split the long SHA256 digest to two lines in small text mode UI
          details << INDENT + sha256[0..59]
          details << INDENT + sha256[60..-1]
        else
          details << INDENT + sha256
        end
      end

      "\n\n" + details.join("\n")
    end

    def self.cert_name_details(x509_name)
      # label followed by the SSL certificate identification
      details = [ INDENT + _("Common Name (CN): ") + Helpers.find_name_attribute(x509_name, "CN") ]
      # label followed by the SSL certificate identification
      details << INDENT + _("Organization (O): ") + Helpers.find_name_attribute(x509_name, "O")
      # label followed by the SSL certificate identification
      details << INDENT + _("Organization Unit (OU): ") + Helpers.find_name_attribute(x509_name, "OU")
    end

    def self.import_ssl_certificate(cert)
      # run the import dialog, check the user selection
      if UI::ImportCertificateDialog.run(cert) != :import
        log.info "Certificate import rejected"
        return false
      end

      cn = Helpers.find_name_attribute(cert.subject, "CN")
      log.info "Importing '#{cn}' certificate..."

      # progress label
      result = Yast::Popup.Feedback(_("Importing the SSL certificate"),
        _("Importing '%s' certificate...") % cn) do

        ::SUSE::Connect::SSLCertificate.import(cert)
      end

      log.info "Certificate import result: #{result}"
      true
    end

  end

end
