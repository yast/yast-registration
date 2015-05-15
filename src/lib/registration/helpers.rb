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
require "erb"

require "registration/addon"
require "registration/registration"
require "registration/storage"
require "registration/url_helpers"
require "suse/connect"

module Registration
  class Helpers
    include Yast::Logger
    extend Yast::I18n

    textdomain "registration"

    Yast.import "Installation"
    Yast.import "Linuxrc"
    Yast.import "Mode"
    Yast.import "Stage"
    Yast.import "Report"
    Yast.import "SlpService"

    # reg. code replacement
    FILTERED = "[FILTERED]"

    # Get the current language (without encoding suffix)
    # @return [String,nil] the current language or nil if set to "POSIX" or "C"
    def self.current_language
      lang = Yast::WFM.GetLanguage
      log.info "Current language: #{lang}"

      if lang == "POSIX" || lang == "C"
        log.info "Ignoring #{lang.inspect} language"
        return nil
      end

      # remove the encoding (e.g. ".UTF-8")
      lang.sub(/\..*$/, "")
    end

    # Get the language for using in HTTP requests (in "Accept-Language" header)
    # @return [String,nil] the language or nil if set to "POSIX" or "C"
    def self.http_language
      lang = current_language
      return nil unless lang

      # replace lang/country separator "_" -> "-"
      # see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.4
      lang.tr!("_", "-")

      log.info "Language for HTTP requests set to #{lang.inspect}"
      lang
    end

    # Create radio button label for a SLP service
    # @param service [Yast::SlpServiceClass::Service] SLP service
    # @return [String] label
    def self.service_description(service)
      url  = UrlHelpers.service_url(service.slp_url)
      descr = service.attributes.to_h[:description]

      # display URL and the description if it is present
      (descr && !descr.empty?) ? "#{descr} (#{url})" : url
    end

    # run the network configuration module
    def self.run_network_configuration
      log.info "Running network configuration..."
      Yast::WFM.call("inst_lan", [{ "skip_detection" => true }])
    end

    # check if the network configuration module is present
    # @return [Boolean] true if the network configuration client is present
    def self.network_configurable
      Yast::WFM.ClientExists("inst_lan")
    end

    # return base version
    # "12-1.47" => "12"
    # "12-1" => "12"
    # "12.1-1.47" => "12.1"
    # "12.1-1" => "12.1"
    def self.base_version(version)
      version.sub(/-.*\z/, "")
    end

    # check if insecure registration is requested
    # (the "reg_ssl_verify=0" boot commandline option is used)
    def self.insecure_registration
      # check the boot parameter only at installation/update
      if Yast::Mode.installation || Yast::Mode.update
        reg_ssl_verify = Yast::Linuxrc.InstallInf("reg_ssl_verify")
        log.info "Boot reg_ssl_verify option: #{reg_ssl_verify.inspect}"

        return reg_ssl_verify == "0"
      else
        config = SUSE::Connect::Config.new
        return config.insecure
      end
    end

    # copy the imported SSL certificate to the target system (if exists)
    def self.copy_certificate_to_target
      cert_file = SUSE::Connect::SSLCertificate::SERVER_CERT_FILE
      # any certificate imported?
      if File.exist?(cert_file)
        # copy the imported certificate
        log.info "Copying SSL certificate (#{cert_file}) to the target system..."
        cert_target_file = File.join(Yast::Installation.destdir, cert_file)
        ::FileUtils.mkdir_p(File.dirname(cert_target_file))
        ::FileUtils.cp(cert_file, cert_target_file)

        # update the certificate links
        cmd = SUSE::Connect::SSLCertificate::UPDATE_CERTIFICATES
        log.info "Updating certificate links (#{cmd})..."
        Yast::SCR.Execute(Yast::Path.new(".target.bash"), cmd)
      end
    end

    # write the current configuration to the configuration file
    def self.write_config
      config_params = {
        url:      UrlHelpers.registration_url,
        insecure: insecure_registration
      }

      log.info "writing registration config: #{config_params}"

      SUSE::Connect::YaST.write_config(config_params)
    end

    def self.reset_registration_status
      file = ::Registration::Registration::SCC_CREDENTIALS
      return unless File.exist?(file)

      log.info "Resetting registration status, removing #{file}"
      File.unlink(file)
    end

    # TODO: move it to yast2 to share it
    def self.render_erb_template(file, binding)
      # use erb template for rendering the richtext summary

      erb_file = Pathname.new(file).absolute? ? file :
        File.expand_path(File.join("../../../data/registration", file), __FILE__)

      log.info "Loading ERB template #{erb_file}"
      erb = ERB.new(File.read(erb_file))

      # render the ERB template in the context of the requested object
      erb.result(binding)
    end

    def self.collect_autoyast_config(known_reg_codes)
      options = Storage::InstallationOptions.instance
      configuration = {
        "do_registration" => true,
        "email"           => options.email,
        "reg_code"        => options.reg_code,
        "install_updates" => options.install_updates
      }

      reg_server = UrlHelpers.registration_url
      configuration["reg_server"] = reg_server if reg_server

      if options.imported_cert_sha256_fingerprint
        configuration["reg_server_cert_fingerprint_type"] = "SHA256"
        configuration["reg_server_cert_fingerprint"] = options.imported_cert_sha256_fingerprint
      end

      configuration["addons"] = Addon.registered.map do |addon|
        addon_hash = addon.to_h(release_type_string: true)
        addon_hash["reg_code"] = known_reg_codes[addon.identifier] || ""
        addon_hash
      end

      configuration
    end

    # Hide registration codes in Autoyast data
    # The result should be just logged, the result might not be a full duplicate
    # of the input is all cases and therefore should NOT be modified.
    # @param settings input value
    # @return either the original value or a value with replaced "reg_code" entries
    # TODO: move AutoYast settings to a separate class and override #to_s
    def self.hide_reg_codes(settings)
      return settings unless settings.is_a?(Hash)

      # create a duplicate
      filtered = settings.dup
      filtered["reg_code"] &&= FILTERED

      return filtered unless filtered["addons"]

      # duplicate the nested values
      filtered["addons"] = filtered["addons"].map(&:dup)

      filtered["addons"].each do |addon|
        addon["reg_code"] &&= FILTERED
      end

      filtered
    end

    def self.report_no_base_product
      # error message
      msg = _("The base product was not found,\ncheck your system.") + "\n\n"

      if Yast::Stage.initial
        # TRANSLATORS: %s = bugzilla URL
        msg += _("The installation medium or the installer itself is seriously broken.\n" \
            "Report a bug at %s.") % "https://bugzilla.suse.com"
      else
        msg += _("Make sure a product is installed and /etc/products.d/baseproduct\n" \
            "is a symlink pointing to the base product .prod file.")
      end

      Yast::Report.Error(msg)
    end
  end
end
