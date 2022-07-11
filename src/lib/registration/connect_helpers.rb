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
require "ui/text_helpers"

require "registration/exceptions"
require "registration/helpers"
require "registration/smt_status"
require "registration/ssl_certificate"
require "registration/ssl_certificate_details"
require "registration/ssl_error_codes"
require "registration/storage"
require "registration/ui/import_certificate_dialog"
require "registration/ui/failed_certificate_popup"
require "registration/url_helpers"

module Registration
  # FIXME: change to a module and include it in the clients
  class ConnectHelpers
    include Yast::Logger
    extend ::UI::TextHelpers
    extend Yast::I18n

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
    # @param silent_reg_code_mismatch [Boolean] true if no popup should be shown
    #   if a registration code is provided
    #   that does not match the registered product.
    #   It still returns false.
    # @return [Boolean] success
    def self.catch_registration_errors(message_prefix: "",
      show_update_hint: false,
      silent_reg_code_mismatch: false,
      &block)
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
        retry if report_error_and_retry?(message_prefix + _("Connection timed out."),
          _("Make sure that the registration server is reachable and\n" \
            "the connection is reliable."))

        false
      rescue SUSE::Connect::ApiError => e
        log.error "Received error: #{e.response.inspect}"
        error_msg = e.message || ""
        # TRANSLATORS: %d is an integer
        error_code_message = _("HTTP error code: %d\n") % e.code
        case e.code
        when 401
          add_update_hint(error_msg) if show_update_hint
          report_error(message_prefix + _("Connection to registration server failed."),
            error_code_message + error_msg)
        when 404
          # update the message when an old SMT/RMT server is found
          check_smt_api(error_msg)
          report_error(message_prefix + _("Connection to registration server failed."),
            error_code_message + error_msg)
        when 422
          if silent_reg_code_mismatch
            log.info "Reg code does not work for this product."
          else
            # Error popup
            report_error(message_prefix + _("Connection to registration server failed."),
              error_code_message + error_msg)
          end
        when 400..499
          report_error(message_prefix + _("Registration client error."),
            error_code_message + error_msg)
        when 500..599
          report_error(message_prefix + _("Registration server error.\n" \
                "Retry the operation later."), error_msg)
        else
          report_error(message_prefix + _("Connection to registration server failed."),
            error_code_message + error_msg)
        end
        false
      rescue ::Registration::ServiceError => e
        log.error("Service error: #{e.message % e.service}")
        report_pkg_error(_(e.message) % e.service)
        false
      rescue ::Registration::PkgError => e
        log.error("Pkg error: #{e.message}")
        report_pkg_error(_(e.message))
        false
      rescue OpenSSL::SSL::SSLError => e
        log.error "OpenSSL error: #{e}"
        should_retry = handle_ssl_error(e, certificate_imported)
        if should_retry
          certificate_imported = true
          retry
        end
        false
      rescue JSON::ParserError => e
        log.error "JSON parse error"
        # update the message when an old SMT/RMT server is found
        check_smt_api(e.message)
        details_error(message_prefix + _("Cannot parse the data from server."), e.message)
        false
      rescue StandardError => e
        log.error("SCC registration failed: #{e.class}: #{e}, #{e.backtrace}")
        Yast::Report.Error(
          error_with_details(message_prefix + _("Connection to registration server failed."),
            e.message)
        )
        false
      end
    end

    def self.report_error(msg, error_message)
      Yast::Report.Error(error_with_details(msg, error_message))
    end

    def self.details_error(msg, error_message, retry_button: false)
      if Yast::Mode.auto && !retry_button
        # AY mode and no retry button available
        report_error(msg, error_message)
        return
      end

      buttons =
        if retry_button
          { retry: Yast::Label.RetryButton, cancel: Yast::Label.CancelButton }
        else
          :ok
        end
      Yast2::Popup.show(msg, details: error_message, headline: :error, buttons: buttons)
    end

    def self.report_error_and_retry?(msg, details_message)
      details_error(msg, details_message, retry_button: true) == :retry
    end

    # Report a pkg-bindings error. Display a message with error details from
    # libzypp.
    # @param msg [String] error message (translated)
    def self.report_pkg_error(msg)
      report_error(msg, Yast::Pkg.LastError)
    end

    def self.error_with_details(error, details)
      return error if !details || details.empty?

      # %s are error details
      details_msg = _("Details: %s") % details
      displayinfo = Yast::UI.GetDisplayInfo || {}

      return (error + "\n\n" + details_msg) unless displayinfo["TextMode"]

      # Use almost the max width available
      max_size = (displayinfo["Width"] || 80) - 4

      error + "\n\n" + wrap_text(details_msg, max_size)
    end

    # @param error [OpenSSL::SSL::SSLError]
    # @param certificate_imported [Boolean] have we already imported the certificate?
    # @return [Boolean] should the `rescue` clause `retry`?
    def self.handle_ssl_error(error, certificate_imported)
      cert = Storage::SSLErrors.instance.ssl_failed_cert
      error_code = Storage::SSLErrors.instance.ssl_error_code
      expected_cert_type = Storage::Config.instance.reg_server_cert_fingerprint_type

      # in non-AutoYast mode ask the user to import the certificate
      if !Yast::Mode.autoinst && cert && SslErrorCodes::IMPORT_ERROR_CODES.include?(error_code)
        # retry after successfull import
        return true if ask_import_ssl_certificate(cert, error_code)
      # in AutoYast mode check whether the certificate fingerprint match
      # the configured value (if present)
      elsif Yast::Mode.autoinst && cert && expected_cert_type && !expected_cert_type.empty?
        expected_fingerprint = Fingerprint.new(expected_cert_type,
          Storage::Config.instance.reg_server_cert_fingerprint)

        if cert.fingerprint(expected_cert_type) == expected_fingerprint
          # import the certificate and retry (just once)
          if !certificate_imported
            import_ssl_certificate(cert)
            return true
          end

          report_ssl_error(error.message, cert, error_code)
        else
          # error message
          Yast::Report.Error(_("Received SSL Certificate does not match " \
                "the expected certificate."))
        end
      elsif Yast::Mode.autoinst && Storage::Config.instance.reg_server_cert &&
          !Storage::Config.instance.reg_server_cert.empty?

        # try just once to avoid endless loop
        if !certificate_imported
          cert_url = Storage::Config.instance.reg_server_cert
          log.info "Importing certificate from #{cert_url}..."
          cert = SslCertificate.download(cert_url)
          return true if cert.import
        end

        report_ssl_error(error.message, cert, error_code)
      else
        report_ssl_error(error.message, cert, error_code)
      end
      false
    end

    def self.ask_import_ssl_certificate(cert, error_code)
      # run the import dialog, check the user selection
      if UI::ImportCertificateDialog.run(cert, error_code) != :import
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

    def self.report_ssl_error(message, cert, error_code)
      UI::FailedCertificatePopup.show(message, cert, error_code)
    end

    # Check whether the registration server provides the old NCC API,
    # if yes it replaces the error message with a hint about old registration server
    # @param error_msg [String] the received error message, the content might be replaced
    def self.check_smt_api(error_msg)
      url = UrlHelpers.registration_url
      # no SMT/RMT/custom server used
      return if url == SUSE::Connect::YaST::DEFAULT_URL

      # test old SMT/RMT instance
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

      error_msg.replace(msg)
    end

    # @param [String] message_prefix prefix displayed in the error message
    # @param [Exception] e caught exception for displaying the details
    def self.handle_network_error(message_prefix, e)
      if Yast::NetworkService.isNetworkRunning
        # FIXME: use a better message, this one has been reused after the text freeze
        report_error(message_prefix + _("Invalid URL."), e.message)
      elsif Helpers.network_configurable && !Yast::Mode.auto
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

    # Add SCC synchronization hint into the text message when using the SCC
    # registration server.
    # @param error_msg [String] the error message from the registratino server,
    #   the hint is appended at the end
    def self.add_update_hint(error_msg)
      # TRANSLATORS: additional hint for an error message
      msg = _("Check that this system is known to the registration server.")

      # probably missing NCC->SCC sync, display a hint unless SMT/RMT is used
      if [nil, SUSE::Connect::YaST::DEFAULT_URL].include?(UrlHelpers.registration_url)

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
      error_msg << "\n\n\n" unless error_msg.empty?
      error_msg << msg
    end

    private_class_method :report_error, :error_with_details, :import_ssl_certificate,
      :report_ssl_error, :check_smt_api, :handle_network_error, :details_error,
      :report_error_and_retry?
  end
end
