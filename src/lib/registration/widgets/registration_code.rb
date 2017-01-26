# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE.
#
# To contact SUSE about this file by physical or electronic mail, you may find
# current contact information at www.suse.com.
# ------------------------------------------------------------------------------

require "yast"
require "cwm/widget"
require "uri"
require "registration/registration_ui"

module Registration
  module Widgets
    class RegistrationCode < CWM::InputField
      VALID_URL_SCHEMES = ["http", "https"].freeze

      attr_accessor :registration_code, :registration, :reg_options

      def initialize
        textdomain "registration"
      end

      def label
        _("Registration Code or SMT Server URL")
      end

      # Initialize the widget with stored values
      def init
        log.info("Already registered") if registered?

        @options = Storage::InstallationOptions.instance
        self.value = @options.custom_url
        self.value = @options.reg_code if !@options.reg_code.to_s.empty?
      end

      # Set registration options according to the value
      def store
        if valid_url?
          @options.reg_code   = ""
          @options.custom_url = value
        else
          @options.reg_code   = value
          @options.custom_url = default_url
        end
      end

      def registered?
        Registration.is_registered?
      end

      def register
        return true if skip?

        log.info("Registering the system and the base product.")
        return false if !register_system_and_base_product

        log.info("System registered with success.")
        Storage::InstallationOptions.instance.base_registered = true
      end

    private

      def valid_url?
        return false if value.to_s.empty?

        uri = URI(value)
        VALID_URL_SCHEMES.include?(uri.scheme)
      end

      # run the system and the base product registration
      # @return [Boolean] true on success
      def register_system_and_base_product
        url = UrlHelpers.registration_url
        return false if UrlHelpers.registration_url == :cancel

        registration    = Registration.new(url)
        registration_ui = RegistrationUI.new(registration)

        success, product_service = registration_ui.register_system_and_base_product

        if product_service && !registration_ui.install_updates?
          registration_ui.disable_update_repos(product_service)
        end

        success
      end

      # Default registration server
      #
      # The boot_url takes precedence over the SUSE::Connect default
      # one.
      #
      # @return [String] URL for the registration server
      def default_url
        boot_url || SUSE::Connect::Config.new.url
      end

      # Registration server URL given through Linuxrc
      #
      # @return [String,nil] URL for the registration server; nil if not given.
      def boot_url
        UrlHelpers.boot_reg_url
      end

      # Skip registration if the value is empty or nil
      def skip?
        value.to_s.empty?
      end
    end
  end
end
