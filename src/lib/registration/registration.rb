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
        :distro_target => distro_target,
        :email => email
      )

      login, password = SUSE::Connect::YaST.announce_system(settings)
      credentials = SUSE::Connect::Credentials.new(login, password, SCC_CREDENTIALS)

      log.info "Global SCC credentials: #{credentials}"

      # ensure the zypp config directories are writable in inst-sys
      ::Registration::SwMgmt.zypp_config_writable!

      # write the global credentials
      credentials.write
    end


    def register_products(products)
      product_services = products.map do |product|

        product_ident = {
          :arch         => product["arch"],
          :name         => product["name"],
          :version      => product["version"],
          :release_type => product["release_type"]
        }
        log.info "Registering product: #{product_ident}"

        params = connect_params(:product_ident => product_ident)

        # use product specific reg. code (e.g. for addons)
        params[:token] = product["reg_code"] if product["reg_code"]

        SUSE::Connect::YaST.activate_product(params)
      end

      log.info "registered product_services: #{product_services.inspect}"

      if !product_services.empty?
        credentials = SUSE::Connect::Credentials.read(SCC_CREDENTIALS)
        ::Registration::SwMgmt.add_services(product_services, credentials)
      end

      product_services
    end

    def get_addon_list
      # extensions for base product
      base_product = ::Registration::Storage::BaseProduct.instance.product
      params = connect_params(:product_ident => {:name => base_product["name"]})

      log.info "Reading available addons for product: #{base_product["name"]}"
      SUSE::Connect::YaST.list_products(params)
    end

    def self.is_registered?
      SUSE::Connect::System.registered?
    end

    private

    def connect_params(params)
      default_params = {
        :language => ::Registration::Helpers.language,
        :debug => ENV["SCCDEBUG"],
        :verbose => ENV["Y2DEBUG"] == "1",
        # pass a verify_callback to get details about failed SSL verification
        :verify_callback => lambda do |verify_ok, context|
          # we cannot raise an exception with details here (all exceptions in
          # verify_callback are caught and ignored), we need to store the error
          # details is a global instance
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
