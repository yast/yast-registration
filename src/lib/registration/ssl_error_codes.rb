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

require "yast"

module Registration
  # This class defines constants and translations for the most common OpenSSL errors
  # @see https://www.openssl.org/docs/apps/verify.html
  # @see https://github.com/openssl/openssl/blob/2c75f03b39de2fa7d006bc0f0d7c58235a54d9bb/include/openssl/x509_vfy.h#L99-L189
  module SslErrorCodes
    extend Yast::I18n
    textdomain "registration"

    # "certificate has expired"
    EXPIRED = 10
    # "self signed certificate"
    SELF_SIGNED_CERT = 18
    # "self signed certificate in certificate chain"
    SELF_SIGNED_CERT_IN_CHAIN = 19
    # "unable to get local issuer certificate"
    NO_LOCAL_ISSUER_CERTIFICATE = 20

    # openSSL error codes for which the import SSL certificate dialog is shown,
    # for the other error codes just the error message is displayed
    # (importing the certificate would not help)
    IMPORT_ERROR_CODES = [
      SELF_SIGNED_CERT,
      SELF_SIGNED_CERT_IN_CHAIN
    ].freeze

    # error code => translatable error message
    # @note the text messages need to be translated at runtime via _() call
    # @note we do not translate every possible OpenSSL error message, just the most common ones
    OPENSSL_ERROR_MESSAGES = {
      # TRANSLATORS: SSL error message
      EXPIRED                     => N_("Certificate has expired"),
      # TRANSLATORS: SSL error message
      SELF_SIGNED_CERT            => N_("Self signed certificate"),
      # TRANSLATORS: SSL error message
      SELF_SIGNED_CERT_IN_CHAIN   => N_("Self signed certificate in certificate chain"),
      # TRANSLATORS: SSL error message
      NO_LOCAL_ISSUER_CERTIFICATE => N_("Unable to get local issuer certificate")
    }.freeze
  end
end
