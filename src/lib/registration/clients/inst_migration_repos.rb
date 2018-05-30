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

        # import the SMT certificate to inst-sys
        import_ssl_certificate
      end

      # Import the old SSL certificate if present. Tries both SLE12 nad SLE11
      # file locations.
      def import_ssl_certificate
        # add the /mnt prefix
        target_files = SslCertificate::PATHS.map { |f| File.join(Yast::Installation.destdir, f) }
        # find existing file
        cert_file = target_files.find { |f| File.exist?(f) }

        if cert_file
          log.info("Importing the SSL certificate from the old system (#{cert_file})...")
          cert = SslCertificate.load_file(cert_file)
          # in Stage.initial this imports to the inst-sys
          cert.import
        else
          log.info("No custom SSL certificate found in the system")
        end
      end
    end
  end
end
