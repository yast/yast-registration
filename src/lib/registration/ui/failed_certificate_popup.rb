# typed: false
# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# ------------------------------------------------------------------------------
#

require "erb"
require "yast"

require "registration/helpers"
require "registration/ssl_certificate"
require "registration/ssl_certificate_details"
require "registration/ssl_error_codes"
require "registration/url_helpers"

module Registration
  module UI
    # This class displays a popup with a SSL certificate error
    class FailedCertificatePopup
      include Yast::I18n
      include ERB::Util

      attr_accessor :certificate, :error_code, :message

      Yast.import "Report"
      Yast.import "Stage"
      Yast.import "Directory"

      # create and display the error popup
      # @param msg [String,nil] the original OpenSSL error message
      #   (used as a fallback when a translated message is not found)
      # @param cert [Registration::SslCertitificate] certificate to display
      # @param error_code [Integer] OpenSSL error code
      def self.show(msg, cert, error_code)
        popup = FailedCertificatePopup.new(msg, cert, error_code)
        popup.show
      end

      # the constructor
      # @param msg [String,nil] the original OpenSSL error message
      #   (used as a fallback when a translated message is not found)
      # @param cert [Registration::SslCertitificate] certificate to display
      # @param error_code [Integer] OpenSSL error code
      def initialize(msg, cert, error_code)
        textdomain "registration"

        @certificate = cert
        @message = msg
        @error_code = error_code
      end

      # display the popup and wait for clicking the [OK] button
      def show
        # this uses a RichText message format
        Yast::Report.LongError(ssl_error_message)
      end

    private

      # Build the message displayed in the popup
      # @return [String] message in RichText format
      def ssl_error_message
        # try to use a translatable message first, if not found then use
        # the original error message from openSSL
        @url = UrlHelpers.registration_url || SUSE::Connect::YaST::DEFAULT_URL
        @msg = _(SslErrorCodes::OPENSSL_ERROR_MESSAGES[error_code]) || message

        Helpers.render_erb_template("certificate_error.erb", binding)
      end

      # the command which needs to be called to import the SSL certificate
      # @return [String] command
      def import_command
        if Yast::Stage.initial
          File.join(Yast::Directory.bindir, "install_ssl_certificates")
        else
          "update-ca-certificates"
        end
      end
    end
  end
end
