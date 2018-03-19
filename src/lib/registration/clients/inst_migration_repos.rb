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

        # initialize the target path
        set_target_path

        # call the normal client
        Yast::WFM.call("migration_repos", [{ "enable_back" => true }])
      end

    private

      # Pass the target directory to SUSEConnect
      def set_target_path
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
        # SLE12 certificate path
        cert_file = File.join(Yast::Installation.destdir, SUSE::Connect::YaST::SERVER_CERT_FILE)

        if !File.exist?(cert_file)
          # try the the SLE11 certificate path as well
          # see https://github.com/yast/yast-registration/blob/Code-11-SP3/src/modules/Register.ycp#L296-L297
          cert_file = File.join(Yast::Installation.destdir,
            "/etc/ssl/certs/registration-server.pem")
          return unless File.exist?(cert_file)
        end

        log.info("Importing the SSL certificate from the old system (#{cert_file})...")
        cert = SslCertificate.load_file(cert_file)
        # in Stage.initial this imports to the inst-sys
        cert.import
      end
    end
  end
end
