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
    BOOT_PARAM = "reg_url".freeze

    # SLP service name
    SLP_SERVICE = "registration.suse".freeze

    # Evaluate the registration URL to use
    # @see https://github.com/yast/yast-registration/wiki/Changing-the-Registration-Server
    # for details
    # @return [String,nil,Symbol] registration URL, nil means use the default,
    #           :cancel means that the user aborted the selection
    def self.registration_url
      # cache the URL to use the same server for all operations
      cache = ::Registration::Storage::Cache.instance
      return cache.reg_url if cache.reg_url_cached

      log.info "Evaluating the registration URL in #{Yast::Mode.mode.inspect} mode"

      url = case Yast::Mode.mode
      when "installation"
        reg_url_at_installation
      when "normal"
        reg_url_at_running_system
      when "update"
        reg_url_at_upgrade
      when "autoupgrade", "autoinstallation"
        reg_url_from_autoyast_config
      else
        log.warn "Unknown mode: #{Yast::Mode.mode}, using default URL"
        # use the default
        nil
      end

      # SLP selection canceled, do not cache it
      return url if url == :cancel

      # cache the URL
      cache.reg_url = url
      cache.reg_url_cached = true
      url
    end

    # @return [void]
    def self.reset_registration_url
      ::Registration::Storage::Cache.instance.reg_url = nil
      ::Registration::Storage::Cache.instance.reg_url_cached = false
    end

    # convert service URL to plain URL, remove the SLP service prefix
    # "service:registration.suse:smt:https://scc.suse.com/connect" ->
    # "https://scc.suse.com/connect"
    # @param service [String]
    # @return [String]
    def self.service_url(service)
      service.sub(/\Aservice:#{Regexp.escape(SLP_SERVICE)}:[^:]+:/, "")
    end

    # @return [String] "credentials" parameter from URL
    # @raise [URI::InvalidURIError] if URL is invalid
    # @param url [String] URL as string
    def self.credentials_from_url(url)
      parsed_url = URI(url)
      params = Hash[URI.decode_www_form(parsed_url.query)]

      params["credentials"]
    end

    # get registration URL in installation mode
    # @return (see registration_url)
    def self.reg_url_at_installation
      custom_url = ::Registration::Storage::InstallationOptions.instance.custom_url
      return custom_url if custom_url && !custom_url.empty?

      # boot command line if present and not empty (see bsc#1010387)
      boot_url = boot_reg_url
      return boot_url if boot_url && !boot_url.empty?

      # if no SLP is selected nil is returned which means the default URL
      slp_service_url
    end

    # get registration URL from AutoYaST configuration file
    # @return (see registration_url)
    def self.reg_url_from_autoyast_config
      server = ::Registration::Storage::Config.instance.reg_server
      return server if server && !server.empty?
      SUSE::Connect::YaST::DEFAULT_URL
    end

    # get registration URL in upgrade mode
    # @return (see registration_url)
    def self.reg_url_at_upgrade
      # in online upgrade mode behave like in installed system
      return reg_url_at_running_system if Yast::Installation.destdir == "/"

      custom_url = ::Registration::Storage::InstallationOptions.instance.custom_url
      return custom_url if custom_url && !custom_url.empty?

      # boot command line if present
      boot_url = boot_reg_url
      return boot_url if boot_url

      # check for suse_register config only when NCC credentials file exists
      # (the config file exists even on a not registered system)
      dir = SUSE::Connect::YaST::DEFAULT_CREDENTIALS_DIR
      ncc_creds = File.join(Yast::Installation.destdir, dir, "NCCcredentials")
      scc_creds = File.join(Yast::Installation.destdir, SUSE::Connect::Config::DEFAULT_CONFIG_FILE)

      # do not use the old URL when it has failed before
      if !::Registration::Storage::Cache.instance.upgrade_failed
        if File.exist?(scc_creds)
          config = SUSE::Connect::Config.new(scc_creds)
          return config.url
        end
        if File.exist?(ncc_creds)
          old_conf = SuseRegister.new(Yast::Installation.destdir)
          if old_conf.found?
            # use default if ncc was used in past
            return nil if old_conf.ncc?
            # if specific server is used, then also use it
            return old_conf.stripped_url.to_s
          end
        end
      end

      # if no SLP is selected nil is returned which means the default URL
      slp_service_url
    end

    # get registration URL in running system
    # @return (see registration_url)
    def self.reg_url_at_running_system
      custom_url = ::Registration::Storage::InstallationOptions.instance.custom_url
      return custom_url if custom_url && !custom_url.empty?

      # check for previously saved config value
      if File.exist?(SUSE::Connect::YaST::DEFAULT_CONFIG_FILE)
        config = SUSE::Connect::Config.new
        return config.url
      end

      # if no SLP is selected nil is returned which means the default URL
      slp_service_url
    end

    # @return [String,nil] the boot command line parameter
    def self.boot_reg_url
      reg_url = Yast::Linuxrc.InstallInf("regurl")
      log.info "Boot regurl option: #{reg_url.inspect}"

      reg_url
    end

    private_class_method :reg_url_at_running_system, :reg_url_at_upgrade,
      :reg_url_at_installation

    # @return (see registration_url)
    def self.slp_service_url
      log.info "Starting SLP discovery..."
      url = Yast::WFM.call("discover_registration_services")
      log.info "Selected SLP service: #{url.inspect}"

      url
    end

    # @return [Array<Yast::SlpServiceClass::Service>]
    def self.slp_discovery
      log.info "Searching for #{SLP_SERVICE} SLP services"
      services = Yast::SlpService.all(SLP_SERVICE)
      log.debug "Found services: #{services.inspect}"

      # ignore SUSE manager registration servers (bnc#894470)
      services.reject! { |service| service.slp_url.start_with?("service:#{SLP_SERVICE}:manager:") }

      log.info "Found #{services.size} services: #{services.map(&:slp_url).inspect}"
      services
    end

    # @return [Array<Yast::SlpServiceClass::Service>]
    def self.slp_discovery_feedback
      Yast::Popup.Feedback(_("Searching..."), _("Looking up local registration servers...")) do
        slp_discovery
      end
    end
  end
end
