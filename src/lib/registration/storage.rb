
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

require "singleton"

module Registration

  # a module holding data needed during (auto)installation
  module Storage

    # storage for changed repositories
    class RegCodes < Struct.new(:reg_codes)
      include Singleton
    end

    # remember the values entered by user
    class InstallationOptions
      include Singleton

      attr_accessor :install_updates, :email, :reg_code, :selected_addons, :base_registered

      def initialize
        @email = ""
        @reg_code = ""
        @selected_addons = []
        @base_registered = false
      end
    end

    class Cache < Struct.new(:available_addons, :reg_url, :reg_url_cached)
      include Singleton
    end

    # remember the details about SSL verification failure
    # the attributes are read from
    class SSLErrors < Struct.new(:ssl_error_code, :ssl_error_msg, :ssl_failed_cert)
      include Singleton

      def reset
        self.ssl_error_code = nil
        self.ssl_error_msg = nil
        self.ssl_failed_cert = nil
      end
    end

    # AutoYast configuration
    class Config
      include Singleton

      attr_accessor :do_registration, :reg_server, :reg_server_cert, :email,
        :reg_code, :install_updates, :addons, :slp_discovery

      def initialize
        reset
      end

      def reset
        @do_registration = false
        @reg_server = ""
        @reg_server_cert = ""
        @email = ""
        @reg_code = ""
        @install_updates = false
        @addons = []
        @slp_discovery = false
      end

      def export
        ret = { "do_registration" => @do_registration }

        if @do_registration
          ret.merge!(
            {
              "reg_server" => @reg_server,
              "slp_discovery" => @slp_discovery,
              "reg_server_cert" => @reg_server_cert,
              "email" => @email,
              "reg_code" => @reg_code,
              "install_updates" => @install_updates,
              "addons" => @addons
            }
          )
        end

        ret
      end

      def import(settings)
        @do_registration = settings.fetch("do_registration", false)
        @reg_server = settings["reg_server"] || ""
        @slp_discovery = settings.fetch("slp_discovery", false)
        @reg_server_cert = settings["reg_server_cert"] || ""
        @email = settings["email"] || ""
        @reg_code = settings["reg_code"] || ""
        @install_updates = settings.fetch("install_updates", false)
        @addons = settings["addons"] || []
      end
    end
  end
end