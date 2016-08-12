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
require "registration/smt_status"
require "registration/ssl_certificate"
require "registration/ssl_certificate_details"
require "registration/url_helpers"
require "registration/ui/import_certificate_dialog"

module Registration
  # FIXME: change to a module and include it in the clients
  class ConnectHelpers
    include Yast::Logger
    extend Yast::I18n

    # openSSL error codes for which the import SSL certificate dialog is shown,
    # for the other error codes just the error message is displayed
    # (importing the certificate would not help)
    IMPORT_ERROR_CODES = UI::ImportCertificateDialog::OPENSSL_ERROR_MESSAGES.keys

    textdomain "registration"

    Yast.import "Mode"
    Yast.import "Popup"
    Yast.import "Report"
    Yast.import "NetworkService"

    # Call a block, rescuing various exceptions including StandardError.
    # Return a boolean success value instead.
    # @param message_prefix [String] Prefix before error like affected product or addon
    # @param show_update_hint [Boolean] true if an extra hint for registration update
    #   should be displayed
    # @return [Boolean] success
    def self.catch_registration_errors(message_prefix: "", show_update_hint: false, &block)
      # import the SSL certificate just once to avoid an infinite loop
      certificate_imported = false
      begin
        # reset the previous SSL errors
        Storage::SSLErrors.instance.reset

        block.call

        true
      rescue SocketError, Errno::ENETUNREACH => e
        log.error "Network error: #{e.class}: #{e.message}"
        handle_network_error(message_prefix, e)
        false
      rescue Timeout::Error => e
        # Error popup
        log.error "Timeout error: #{e.message}"
        # FIXME: to not break existing translation, this typo should be fixed
        # later after SP2: time -> timed
        Yast::Report.Error(
          error_with_details(message_prefix + _("Connection time out.") + "\n",
            _("Make sure that the registration server is reachable and\n" \
              "the connection is reliable."))
        )
        false
      rescue SUSE::Connect::ApiError => e
        log.error "Received error: #{e.response.inspect}"
        case e.code
        when 401
          if show_update_hint
            # TRANSLATORS: additional hint for an error message
            msg = _("Check that this system is known to the registration server.")

            # probably missing NCC->SCC sync, display a hint unless SMT is used
            if UrlHelpers.registration_url == SUSE::Connect::YaST::DEFAULT_URL
              msg += "\n\n"
              # TRANSLATORS: additional hint for an error message
              msg += _("If you are upgrading from SLE11 make sure the SCC server\n" \
                  "knows the old NCC registration. Synchronization from NCC to SCC\n" \
                  "might take very long time.\n\n" \
                  "If the SLE11 system was installed recently you could log into\n" \
                  "%s to speed up the synchronization process.\n" \
                  "Just wait several minutes after logging in and then retry \n" \
                  "the upgrade again.") % \
                SUSE::Connect::YaST::DEFAULT_URL
            end

            # add the hint to the error details
            e.message << "\n\n\n" + msg
          end

          report_error(message_prefix + _("Connection to registration server failed."), e)
        when 404
          # update the message when an old SMT server is found
          check_smt_api(e)

          report_error(message_prefix + _("Connection to registration server failed."), e)
        when 422
          # Error popup
          report_error(message_prefix + _("Connection to registration server failed."), e)
        when 400..499
          report_error(message_prefix + _("Registration client error."), e)
        when 500..599
          report_error(message_prefix + _("Registration server error.\n" \
                "Retry the operation later."), e)
        else
          report_error(message_prefix + _("Connection to registration server failed."), e)
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
        expected_cert_type = Storage::Config.instance.reg_server_cert_fingerprint_type

        # in non-AutoYast mode ask the user to import the certificate
        if !Yast::Mode.autoinst && cert && IMPORT_ERROR_CODES.include?(error_code)
          # retry after successfull import
          retry if ask_import_ssl_certificate(cert)
          # in AutoYast mode check whether the certificate fingerprint match
          # the configured value (if present)
        elsif Yast::Mode.autoinst && cert && expected_cert_type && !expected_cert_type.empty?
          expected_fingerprint = Fingerprint.new(expected_cert_type,
            Storage::Config.instance.reg_server_cert_fingerprint)

          if cert.fingerprint(expected_cert_type) == expected_fingerprint
            # import the certificate and retry (just once)
            if !certificate_imported
              import_ssl_certificate(cert)
              certificate_imported = true
              retry
            end

            report_ssl_error(e.message, cert)
          else
            # error message
            Yast::Report.Error(_("Received SSL Certificate does not match " \
                  "the expected certificate."))
          end
        else
          report_ssl_error(e.message, cert)
        end

        false
      rescue JSON::ParserError => e
        # update the message when an old SMT server is found
        check_smt_api(e)

        report_error(message_prefix + _("Connection to registration server failed."), e)
      rescue StandardError => e
        log.error("SCC registration failed: #{e.class}: #{e}, #{e.backtrace}")
        Yast::Report.Error(
          error_with_details(message_prefix + _("Connection to registration server failed."),
            e.message)
        )
        false
      end
    end

    def self.report_error(msg, api_error)
      localized_error = api_error.message

      Yast::Report.Error(error_with_details(msg, localized_error))
    end

    def self.error_with_details(error, details)
      return error if !details || details.empty?

      # %s are error details
      error + "\n\n" + (_("Details: %s") % details)
    end

    def self.ssl_error_details(cert)
      return "" if cert.nil?

      details = SslCertificateDetails.new(cert)
      details.summary
    end

    def self.ask_import_ssl_certificate(cert)
      # run the import dialog, check the user selection
      if UI::ImportCertificateDialog.run(cert) != :import
        log.info "Certificate import rejected"
        return false
      end

      import_ssl_certificate(cert)
    end

    # @return [Boolean] true on success, can fail if cannot import or if the cert
    # is not valid after all
    def self.import_ssl_certificate(cert)
      # Has been a certificate already imported? In some cases the certificate
      # import might not help, avoid endless certificate import loop.
      if Storage::InstallationOptions.instance.imported_cert_sha256_fingerprint
        # TRANSLATORS: multiline error message - a SSL certificate has been
        # imported but the registration server still cannot be accessed securely,
        # user has to solve the certificate issue manually.
        Yast::Report.Error(_("A certificate has been already imported\n" \
          "but the server connection still cannot be trusted.\n\n" \
          "Please fix the certificate issue manually, ensure that the server\n" \
          "can be connected securely and start the YaST module again."))

        return false
      end

      cn = cert.subject_name
      log.info "Importing '#{cn}' certificate..."

      # progress label
      result = Yast::Popup.Feedback(_("Importing the SSL certificate"),
        _("Importing '%s' certificate...") % cn) do
        cert.import
      end

      # remember the imported certificate fingerprint for Autoyast export
      Storage::InstallationOptions.instance.imported_cert_sha256_fingerprint =
        cert.fingerprint(Fingerprint::SHA256).value

      log.info "Certificate import result: #{result}"
      result
    end

    def self.report_ssl_error(message, cert)
      # try to use a translatable message first, if not found then use
      # the original error message from openSSL
      error_code = Storage::SSLErrors.instance.ssl_error_code
      msg = UI::ImportCertificateDialog::OPENSSL_ERROR_MESSAGES[error_code]
      msg = msg ? _(msg) : Storage::SSLErrors.instance.ssl_error_msg
      msg = message if msg.nil? || msg.empty?

      Yast::Report.Error(
        error_with_details(_("Secure connection error: %s") % msg, ssl_error_details(cert))
      )
    end

    def self.check_smt_api(e)
      url = UrlHelpers.registration_url
      # no SMT/custom server used
      return if url.nil?

      # test old SMT instance
      smt_status = SmtStatus.new(url, insecure: Helpers.insecure_registration)
      return unless smt_status.ncc_api_present?

      # display just the hostname in the server URL
      display_url = URI(url)
      display_url.path = ""
      display_url.query = nil
      # TRANSLATORS: error message, %s is a server URL,
      # e.g. https://smt.example.com
      msg = _("An old registration server was detected at\n%s.\n" \
          "Make sure the latest product supporting the new registration\n" \
          "protocol is installed at the server.") % display_url

      e.message.replace(msg)
    end

    # @param [String] message_prefix prefix displayed in the error message
    # @param [Exception] e caught exception for displaying the details
    def self.handle_network_error(message_prefix, e)
      if Yast::NetworkService.isNetworkRunning
        # FIXME: use a better message, this one has been reused after the text freeze
        report_error(message_prefix + _("Invalid URL."), e)
      elsif Helpers.network_configurable && !(Yast::Mode.autoinst || Yast::Mode.autoupgrade)
        if Yast::Popup.YesNo(
          # Error popup
          _("Network is not configured, the registration server cannot be reached.\n" \
              "Do you want to configure the network now?")
        )

          Helpers.run_network_configuration
        end
      else
        Yast::Report.Error(_("Network error, check the network configuration."))
      end
    end

    private_class_method :report_error, :error_with_details, :ssl_error_details,
      :import_ssl_certificate, :report_ssl_error, :check_smt_api, :handle_network_error
  end
end
