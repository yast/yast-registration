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

require "scc_api"
require "yast"

require "registration/helpers"
require "registration/sw_mgmt"
require "registration/storage"

module Registration
  class Registration
    include Yast::Logger

    SCC_CREDENTIALS = SccApi::Credentials::DEFAULT_CREDENTIALS_DIR + "/SCCCredentials"

    attr_accessor :url

    def initialize(url = nil)
      @url = url
    end

    def register(email, reg_code)
      @scc = SccApi::Connection.new(email, reg_code)

      # set the current language to receive translated error messages
      @scc.language = ::Registration::Helpers.language

      if @url
        log.info "Using custom registration URL: #{@url.inspect}"
        @scc.url = @url
      end

      # announce (register the system) first
      @credentials = @scc.announce

      # ensure the zypp config directories are writable in inst-sys
      ::Registration::SwMgmt.zypp_config_writable!

      # write the global credentials
      @credentials.write
    end


    def register_products(products)
      product_services = products.map do |product|
        log.info("Registering product: #{product["name"]}")

        begin
          orig_reg_code = @scc.reg_code
          # use product specific reg. key (e.g. for addons)
          @scc.reg_code = product["reg_key"] if product["reg_key"]

          ret = @scc.register(product)
        ensure
          # restore the original base product key
          @scc.reg_code = orig_reg_code
        end

        ret
      end

      log.info "registered product_services: #{product_services.inspect}"

      if !product_services.empty?
        add_product_services(product_services)
      end

      product_services
    end

    def add_product_services(product_services)
      ::Registration::SwMgmt.add_services(product_services, @credentials)
    end

    def get_addon_list
      # extensions for base product
      ::Registration::Storage::BaseProducts.instance.products.reduce([]) do |acc, product|
        acc.concat(@scc.extensions_for(product["name"]).extensions)
      end
    end

    def self.is_registered?
      File.exist?(SCC_CREDENTIALS)
    end
  end
end
