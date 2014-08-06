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

require "yast"
require "uri"

require "registration/storage"
require "registration/suse_register"
require "suse/connect"

module Registration

  class UrlHelpers
    include Yast::Logger
    extend Yast::I18n

    textdomain "registration"

    Yast.import "Installation"
    Yast.import "Linuxrc"
    Yast.import "Mode"
    Yast.import "Popup"
    Yast.import "Report"
    Yast.import "SlpService"

    # name of the boot parameter
    BOOT_PARAM = "reg_url"

    # SLP service name
    SLP_SERVICE = "registration.suse"

    # Get the language for using in HTTP requests (in "Accept-Language" header)
    # Evaluate the registration URL to use
    # @see https://github.com/yast/yast-registration/wiki/Changing-the-Registration-Server
    # for details
    # @return [String,nil] registration URL, nil means use the default
    def self.registration_url
      # cache the URL to use the same server for all operations
      cache = ::Registration::Storage::Cache.instance
      return cache.reg_url if cache.reg_url_cached

      # TODO FIXME: handle autoyast mode as well, currently it is handled in scc_auto client
      # see https://github.com/yast/yast-yast2/blob/master/library/general/src/modules/Mode.rb#L105
      url = case Yast::Mode.mode
      when "installation"
        reg_url_at_installation
      when "normal"
        reg_url_at_runnig_system
      when "update"
        reg_url_at_upgrade
      else
        log.warn "Unknown mode: #{Yast::Mode.mode}, using default URL"
        # use the default
        nil
      end

      # SLP selection canceled, do not cache it
      return url if url == :cancel

      # cache the URL
      ::Registration::Storage::Cache.instance.reg_url = url
      ::Registration::Storage::Cache.instance.reg_url_cached = true
      url
    end

    def self.reset_registration_url
      ::Registration::Storage::Cache.instance.reg_url = nil
      ::Registration::Storage::Cache.instance.reg_url_cached = false
    end

    # convert service URL to plain URL, remove the SLP service prefix
    # "service:registration.suse:smt:https://scc.suse.com/connect" ->
    # "https://scc.suse.com/connect"
    def self.service_url(service)
      service.sub(/\Aservice:#{Regexp.escape(SLP_SERVICE)}:[^:]+:/, "")
    end

    # return "credentials" parameter from URL
    # raises URI::InvalidURIError if URL is invalid
    # @param url [String] URL as string
    def self.credentials_from_url(url)
      parsed_url = URI(url)
      params = Hash[URI.decode_www_form(parsed_url.query)]

      params["credentials"]
    end

    # get registration URL in installation mode
    def self.reg_url_at_installation
      custom_url = ::Registration::Storage::InstallationOptions.instance.custom_url
      return custom_url if custom_url && !custom_url.empty?

      # boot command line if present
      boot_url = boot_reg_url
      return boot_url if boot_url

      # SLP discovery
      slp_url = slp_service_url
      return slp_url if slp_url

      # use the default
      nil
    end

    # get registration URL in upgrade mode
    def self.reg_url_at_upgrade
      # boot command line if present
      boot_url = boot_reg_url
      return boot_url if boot_url

      # check for suse_register config only when NCC credentials file exists
      # (the config file exists even on a not registered system)
      dir = SUSE::Connect::Credentials::DEFAULT_CREDENTIALS_DIR
      ncc_creds = File.join(Yast::Installation.destdir, dir, "NCCcredentials")
      if File.exist?(ncc_creds)
        # FIXME check at first new suseconnect conf
        old_conf = SuseRegister.new(Yast::Installation.destdir)

        if old_conf.found?
          # use default if ncc was used in past
          return nil if old_conf.ncc?
          # if specific server is used, then also use it
          return old_conf.stripped_url.to_s
        end
      end

      # try SLP if not registered
      slp_url = slp_service_url
      return slp_url if slp_url

      # use the default
      nil
    end

    # get registration URL in running system
    def self.reg_url_at_runnig_system
      custom_url = ::Registration::Storage::InstallationOptions.instance.custom_url
      return custom_url if custom_url && !custom_url.empty?

      # check for previously saved config value
      config = SUSE::Connect::Config.new
      return config.url if config.url

      # try SLP if not registered yet
      slp_url = slp_service_url
      return slp_url if slp_url

      # use the default
      nil
    end


    # return the boot command line parameter
    def self.boot_reg_url
      reg_url = Yast::Linuxrc.InstallInf("regurl")
      log.info "Boot regurl option: #{reg_url.inspect}"

      reg_url
    end

    private_class_method :reg_url_at_runnig_system, :reg_url_at_upgrade,
      :reg_url_at_installation, :boot_reg_url

    def self.slp_service_url
      log.info "Starting SLP discovery..."
      url = Yast::WFM.call("discover_registration_services")
      log.info "Selected SLP service: #{url.inspect}"

      url
    end

    def self.slp_discovery
      services = []

      log.info "Searching for #{SLP_SERVICE} SLP services"
      services.concat(Yast::SlpService.all(SLP_SERVICE))

      log.debug "Found services: #{services.inspect}"
      log.info "Found #{services.size} services: #{services.map(&:slp_url).inspect}"

      services
    end

    def self.slp_discovery_feedback
      Yast::Popup.Feedback(_("Searching..."), _("Looking up local registration servers...")) do
        slp_discovery
      end
    end

  end
end
