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

require "net/http"
require "uri"
require "openssl"

module Registration

  # module for downloading files, include it in the classes which need
  # HTTP/HTTPS download support
  module Downloader
    include Yast::Logger

    private

    def download_file(file_url, insecure: false)
      file_url = URI(file_url) unless file_url.is_a?(URI)
      http = Net::HTTP.new(file_url.host, file_url.port)

      # switch to HTTPS connection if needed
      if file_url.is_a? URI::HTTPS
        http.use_ssl = true
        http.verify_mode = insecure ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
        log.warn("Warning: SSL certificate verification disabled") if insecure
      else
        log.warn("Warning: Using insecure \"#{file_url.scheme}\" transfer protocol")
      end

      # TODO: handle redirection?
      request = Net::HTTP::Get.new(file_url.request_uri)
      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        return response.body
      else
        log.error "HTTP request failed: Error #{response.code}:#{response.message}: #{response.body}"
        raise "Downloading #{file_url} failed: #{response.message}"
      end
    end

  end
end