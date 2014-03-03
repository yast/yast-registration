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

module Registration

  class Helpers
    include Yast::Logger

    Yast.import "Linuxrc"
    Yast.import "Mode"

    # name of the boot parameter
    BOOT_PARAM = "reg_url"

    # Get the language for using in HTTP requests (in "Accept-Language" header)
    def self.language
      lang = Yast::WFM.GetLanguage
      log.info "Current language: #{lang}"

      if lang == "POSIX" || lang == "C"
        log.warn "Ignoring #{lang.inspect} language for HTTP requests"
        return nil
      end

      # remove the encoding (e.g. ".UTF-8")
      lang.sub!(/\..*$/, "")
      # replace lang/country separator "_" -> "-"
      # see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.4
      lang.tr!("_", "-")

      log.info "Language for HTTP requests set to #{lang.inspect}"
      lang
    end


    # Evaluate the registration URL to use
    # @see https://github.com/yast/yast-registration/wiki/Changing-the-Registration-Server
    # for details
    # @return [String,nil] registration URL, nil means use the default
    def self.registration_url
      if Yast::Mode.installation
        # boot command line if present
        boot_url = boot_reg_url
        return boot_url if boot_url
      end

      # TODO FIXME: add SLP discovery

      # no custom URL, use the default
      nil
    end

    private

    # return the boot command line parameter
    def self.boot_reg_url
      parameters = Yast::Linuxrc.InstallInf("Cmdline")
      return nil unless parameters

      registration_param = parameters.split.grep(/\A#{BOOT_PARAM}=/i).last
      return nil unless registration_param

      reg_url = registration_param.split('=', 2).last
      log.info "Boot reg_url option: #{reg_url.inspect}"

      reg_url
    end

  end
end