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
        import_ssl_certificates
      end

      # Import the old SSL certificate if present. Tries all known locations.
      def import_ssl_certificates
        prefix = Yast::Installation.destdir

        SslCertificate::PATHS.each do |file|
          cert_file = File.join(prefix, file)
          if File.exist?(cert_file)
            log.info("Importing the SSL certificate from the old system: (#{prefix})#{file} ...")
            cert = SslCertificate.load_file(cert_file)
            target_path = File.join(SslCertificate::INSTSYS_CERT_DIR, File.basename(cert_file))
            cert.import_to_instsys(target_path)
          else
            log.debug("SSL certificate (#{prefix})#{file} not found in the system")
          end
        end
      end
    end
  end
end
