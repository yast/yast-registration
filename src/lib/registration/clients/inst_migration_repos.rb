# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC
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
require "yast/suse_connect"
require "registration/sw_mgmt"
require "registration/ssl_certificate"
require "registration/ssl_certificate_details"

module Registration
  module Clients
    # This is just a wrapper around the "migration_repos" client to run it at
    # the upgrade workflow.
    class InstMigrationRepos < Yast::Client
      include Yast::Logger
      extend Yast::I18n

      def main
        textdomain "registration"

        Yast.import "Installation"

        # initialize the inst-sys
        instsys_init

        # call the normal client
        Yast::WFM.call("migration_repos", [{ "enable_back" => true }])
      end

    private

      # activate the configuration from the target system in the current inst-sys
      def instsys_init
        destdir = Yast::Installation.destdir || "/"
        return if destdir == "/"

        # copy the old NCC/SCC credentials to inst-sys
        SwMgmt.copy_old_credentials(destdir)

        # import the SMT/RMT certificate to inst-sys
        SslCertificate.import_from_system
      end

      # Log the certificate details
      # @param cert [Registration::SslCertificate] the SSL certificate
      def log_certificate(cert)
        # log also the dates
        log.info("#{SslCertificateDetails.new(cert).summary}\n" \
        "Issued on: #{cert.issued_on}\nExpires on: #{cert.expires_on}")

        # log a warning for expired certificate
        expires = cert.x509_cert.not_after.localtime
        log.warn("The certificate has EXPIRED! (#{expires})") if expires < Time.now
      end
    end
  end
end
