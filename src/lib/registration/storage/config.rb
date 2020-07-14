# Copyright (c) [2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "suse/connect"
require "registration/registration"

module Registration
  module Storage
    # AutoYast configuration
    class Config
      include Singleton

      attr_accessor :modified, :do_registration, :reg_server, :reg_server_cert, :email,
        :reg_code, :install_updates, :addons, :slp_discovery,
        :reg_server_cert_fingerprint_type, :reg_server_cert_fingerprint

      def initialize
        reset
      end

      def reset
        @modified = false
        @do_registration = false
        @reg_server = ""
        @reg_server_cert = ""
        @email = ""
        @reg_code = ""
        @install_updates = false
        @addons = []
        @slp_discovery = false
        @reg_server_cert_fingerprint_type = nil
        @reg_server_cert_fingerprint = ""
        @connect_status = nil
      end

      def export
        ret = { "do_registration" => do_registration }
        # export only the boolean flag when registration is disabled,
        # all other config values are useless in that case
        return ret unless do_registration

        ret.merge!(
          "reg_server"      => reg_server,
          "slp_discovery"   => slp_discovery,
          "email"           => email,
          "reg_code"        => reg_code,
          "install_updates" => install_updates
        )

        ret["addons"] = export_addons
        ret.merge!(export_ssl_config)

        ret
      end

      def import(settings)
        reset

        @do_registration = settings.fetch("do_registration", false)
        @reg_server = settings["reg_server"] || ""
        @slp_discovery = settings.fetch("slp_discovery", false)
        @reg_server_cert = settings["reg_server_cert"] || ""
        @email = settings["email"] || ""
        @reg_code = settings["reg_code"] || ""
        @install_updates = settings.fetch("install_updates", false)
        @addons = import_addons(settings)
        @reg_server_cert_fingerprint_type = settings["reg_server_cert_fingerprint_type"] || ""
        @reg_server_cert_fingerprint = settings["reg_server_cert_fingerprint"] || ""
      end

      # Read configuration settings from the running system
      def read
        return unless ::Registration::Registration.is_registered?
        config = SUSE::Connect::Config.new
        @email = config.email
        @reg_server = config.url
        @reg_code = base_regcode
        @addons = addons_from_system
        @modified = true
        @do_registration = true
      end

    private

      def import_addons(settings)
        (settings["addons"] || []).map do |a|
          import_addon = a.dup
          # handle "nil" release_type, nil cannot be stored in XML profile
          import_addon["release_type"] = nil if a["release_type"] == "nil"
          import_addon
        end
      end

      def export_addons
        addons.map do |a|
          addon_export = a.dup
          # handle nil release_type at export, nil cannot be stored in XML profile
          addon_export["release_type"] = "nil" if addon_export["release_type"].nil?
          addon_export
        end
      end

      def export_ssl_config
        ret = { "reg_server_cert" => reg_server_cert }

        if reg_server_cert_fingerprint_type && !reg_server_cert_fingerprint_type.empty?
          ret["reg_server_cert_fingerprint_type"] = reg_server_cert_fingerprint_type
          ret["reg_server_cert_fingerprint"] = reg_server_cert_fingerprint
        end

        ret
      end

      # Returns the registration code for the base system
      #
      # @return [String,nil]
      def base_regcode
        base_activation = connect_status.activations.find do |activation|
          activation.service&.product&.isbase
        end
        base_activation && base_activation.regcode
      end

      # Returns the elements for the <addons> section
      #
      # @return [Array<Hash>]
      def addons_from_system
        connect_status.activated_products.each_with_object([]) do |addon, addons|
          next if addon.isbase
          addons << {
            "name"    => addon.identifier,
            "version" => addon.version,
            "arch"    => addon.arch
          }
        end
      end

      # SUSE/Connect status information
      #
      # @return [SUSE::Connect::Status] Status information from SCC
      def connect_status
        @connect_status ||= SUSE::Connect::YaST.status({})
      end
    end
  end
end
