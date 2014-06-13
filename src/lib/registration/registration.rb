# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2014 SUSE LLC
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

require "yast"
require "suse/connect"

require "registration/helpers"
require "registration/sw_mgmt"
require "registration/storage"

module Registration
  class Registration
    include Yast::Logger

    SCC_CREDENTIALS = SUSE::Connect::Credentials::GLOBAL_CREDENTIALS_FILE

    attr_accessor :url

    def initialize(url = nil)
      @url = url
    end

    def register(email, reg_code, distro_target)
      settings = connect_params(
        :token => reg_code,
        :email => email
      )

      login, password = SUSE::Connect::YaST.announce_system(settings, distro_target)
      credentials = SUSE::Connect::Credentials.new(login, password, SCC_CREDENTIALS)

      log.info "Global SCC credentials: #{credentials}"

      # ensure the zypp config directories are writable in inst-sys
      ::Registration::SwMgmt.zypp_config_writable!

      # write the global credentials
      credentials.write
    end


    def register_product(product, email = nil)
      service_for_product(product) do |product_ident, params|
        log.info "Registering product: #{product}"
        SUSE::Connect::YaST.activate_product(product_ident, params, email)
      end
    end

    def upgrade_product(product)
      service_for_product(product) do |product_ident, params|
        log.info "Upgrading product: #{product}"
        SUSE::Connect::YaST.upgrade_product(product_ident, params)
      end
    end

    def get_addon_list
      # extensions for base product
      base_product = ::Registration::SwMgmt.find_base_product

      log.info "Reading available addons for product: #{base_product["name"]}"

      remote_product = SUSE::Connect::Remote::Product.new(
        :arch         => base_product["arch"],
        :identifier   => base_product["name"],
        :version      => base_product["version"],
        :release_type => base_product["release_type"]
      )

      params = connect_params({})
      addons = SUSE::Connect::YaST.show_product(remote_product, params)
      # ignore the base product "addon"
      addons.reject{ |a| a.identifier == base_product["name"] }
    end

    def self.is_registered?
      SUSE::Connect::System.registered?
    end

    private

    def service_for_product(product, &block)
      remote_product = SUSE::Connect::Remote::Product.new(
        :arch         => product["arch"],
        :identifier   => product["name"],
        :version      => product["version"],
        :release_type => product["release_type"]
      )

      log.info "Using product: #{remote_product}"

      params = connect_params({})

      # use product specific reg. code (e.g. for addons)
      params[:token] = product["reg_code"] if product["reg_code"]

      product_service = yield(remote_product, params)

      log.info "registration result: #{product_service}"

      if product_service
        credentials = SUSE::Connect::Credentials.read(SCC_CREDENTIALS)
        ::Registration::SwMgmt.add_service(product_service, credentials)
      end

      product_service
    end

    def connect_params(params)
      default_params = {
        :language => ::Registration::Helpers.language,
        :debug => ENV["SCCDEBUG"],
        :verbose => ENV["Y2DEBUG"] == "1",
        # pass a verify_callback to get details about failed SSL verification
        :verify_callback => lambda do |verify_ok, context|
          # we cannot raise an exception with details here (all exceptions in
          # verify_callback are caught and ignored), we need to store the error
          # details in a global instance
          if !verify_ok
            log.error "SSL verification failed: #{context.error}: #{context.error_string}"
            Storage::SSLErrors.instance.ssl_error_code = context.error
            Storage::SSLErrors.instance.ssl_error_msg = context.error_string
            Storage::SSLErrors.instance.ssl_failed_cert = context.current_cert
          end
          verify_ok
        end
      }

      if @url
        log.info "Using custom registration URL: #{@url.inspect}"
        default_params[:url] = @url
      end

      if Helpers.insecure_registration
        log.warn "SSL certificate check disabled via reg_ssl boot parameter"
        default_params[:insecure] = true
      end

      default_params.merge(params)
    end
  end
end
