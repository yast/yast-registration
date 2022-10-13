
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
require "registration/registration_codes_loader"
require "yast"
require "registration/storage/config"
Yast.import "Stage"

module Registration
  # a module holding data needed during (auto)installation
  module Storage
    # storage for changed repositories
    class RegCodes < Struct.new(:reg_codes)
      include Singleton
      include RegistrationCodesLoader

      def initialize
        self.reg_codes = if Stage.initial
          reg_codes_from_usb_stick || reg_codes_from_install_inf || {}
        else
          {}
        end
      end
    end

    # remember the values entered by user
    # TODO: use Config instead to allow easy export at installation
    class InstallationOptions
      include Singleton

      attr_accessor :install_updates, :email, :reg_code, :selected_addons,
        :base_registered, :custom_url, :imported_cert_sha256_fingerprint, :product

      def initialize
        @email = ""
        @reg_code = ""
        @selected_addons = []
        @base_registered = false
      end
    end

    class Cache < Struct.new(:first_run, :addon_services,
      :reg_url, :reg_url_cached, :rollback, :upgrade_failed)

      include Singleton

      def initialize
        self.addon_services = []
        self.first_run = true
        self.upgrade_failed = false
      end
    end

    # remember the details about SSL verification failure
    # the attributes are read from the SSL error context
    class SSLErrors < Struct.new(:ssl_error_code, :ssl_error_msg, :ssl_failed_cert)
      include Singleton

      def reset
        self.ssl_error_code = nil
        self.ssl_error_msg = nil
        self.ssl_failed_cert = nil
      end
    end
  end
end
