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

    # @param message_prefix [String] Prefix before error like affected product or addon
    # @param show_update_hint [Boolean] true if an extra hint for registration update
    #   should be displayed
    def self.catch_registration_errors(message_prefix: "", show_update_hint: false, &block)
      begin
        # reset the previous SSL errors
        Storage::SSLErrors.instance.reset

        yield

        true
      rescue SocketError, Errno::ENETUNREACH => e
        log.error "Network error: #{e.class}: #{e.message}"
        # Error popup
        if Yast::Mode.installation || Yast::Mode.update
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
        log.error "Received error: #{e.response.inspect}"
        case e.code
        when 401
          if show_update_hint
            # TRANSLATORS: additional hint for an error message
            msg = _("Check that this system is known to the registration server.")

            # probably missing NCC->SCC sync, display a hint unless SMT is used
            if Helpers.registration_url.nil?
              msg += "\n\n"
              # TRANSLATORS: additional hint for an error message
              msg += _("If you are upgrading from SLE11 make sure the SCC server\n" \
                  "knows the old NCC registration. Synchronization from NCC to SCC\n" \
                  "might take very long time.\n\n" \
                  "If the SLE11 system was installed recently you could log into\n" \
                  "%s to speed up the synchronization process.\n" \
                  "Just wait several minutes after logging in and then retry \n" \
                  "the upgrade again.") % \
                SUSE::Connect::Client::DEFAULT_URL
            end

            # add the hint to the error details
            e.message << "\n\n\n" + msg
            report_error(message_prefix + _("Registration failed."), e)
          else
            report_error(message_prefix + _("The e-mail address is not known or\nthe registration code is not valid."), e)
          end
        when 422
          # Error popup
          report_error(message_prefix + _("The e-mail address is not known or\nthe registration code is not valid."), e)
        when 400..499
          report_error(message_prefix + _("Registration client error."), e)
        when 500..599
          report_error(message_prefix + _("Registration server error.\nRetry registration later."), e)
        else
          report_error(message_prefix + _("Registration failed."), e)
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
          msg = e.message if msg.nil? || msg.empty?

          Yast::Report.Error(
            error_with_details(_("Secure connection error: %s") % msg, ssl_error_details)
          )
        end

        false
      rescue Exception => e
        log.error("SCC registration failed: #{e.class}: #{e}, #{e.backtrace}")
        Yast::Report.Error(_("Registration failed."))
        false
      end
    end

    private

    def self.report_error(msg, api_error)
      localized_error = api_error.message

      Yast::Report.Error(error_with_details(msg, localized_error))
    end

    def self.error_with_details(error, details)
      return error if (!details || details.empty?)

      # %s are error details
      error + "\n\n" + (_("Details: %s") % details)
    end

    def self.ssl_error_details()
      # label follwed by a certificate description
      details = []

      cert = Storage::SSLErrors.instance.ssl_failed_cert
      if cert
        details << _("Certificate:")
        details << _("Issued To")
        details.concat(cert_name_details(cert.subject))
        details << ""
        details << _("Issued By")
        details.concat(cert_name_details(cert.issuer))
        details << ""
        details << _("SHA1 Fingerprint: ")
        details << INDENT + ::SUSE::Connect::YaST.cert_sha1_fingerprint(cert)
        details << _("SHA256 Fingerprint: ")

        sha256 = ::SUSE::Connect::YaST.cert_sha256_fingerprint(cert)
        if Yast::UI.TextMode && Yast::UI.GetDisplayInfo["Width"] < 105
          # split the long SHA256 digest to two lines in small text mode UI
          details << INDENT + sha256[0..59]
          details << INDENT + sha256[60..-1]
        else
          details << INDENT + sha256
        end
      end

      details.empty? ? "" : ("\n\n" + details.join("\n"))
    end

    def self.cert_name_details(x509_name)
      details = []
      # label followed by the SSL certificate identification
      details << INDENT + _("Common Name (CN): ") + (Helpers.find_name_attribute(x509_name, "CN") || "")
      # label followed by the SSL certificate identification
      details << INDENT + _("Organization (O): ") + (Helpers.find_name_attribute(x509_name, "O") || "")
      # label followed by the SSL certificate identification
      details << INDENT + _("Organization Unit (OU): ") + (Helpers.find_name_attribute(x509_name, "OU") || "")
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

        ::SUSE::Connect::YaST.import_certificate(cert)
      end

      log.info "Certificate import result: #{result}"
      true
    end

  end

end
