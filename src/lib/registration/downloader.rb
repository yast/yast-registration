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
require "registration/exceptions"
require "suse/toolkit/curlrc_dotfile"

module Registration
  # HTTP/HTTPS download support
  # TODO: move it to yast2 to share it
  class Downloader
    extend Yast::Logger

    # download a remote file via HTTP or HTTPS protocol, if maximum nuber or redirects
    # is reached the download fails with RuntimeError exception
    # @param file_url [String, URI] URL of the file to download
    # @param insecure [Boolean] if true the SSL verification errors are ignored
    # @param allow_redirect [Boolean] true: redirection will be followed
    # @return [String] the contents of the downloaded file
    def self.download(file_url, insecure: false, allow_redirect: true)
      if allow_redirect
        # Taking default value for redirection_count
        download_file(file_url, insecure: insecure)
      else
        # Do not allow redirection
        download_file(file_url, insecure: insecure, redirection_count: 0)
      end
    end

    # internal method which handles HTTP redirects
    # @param file_url [String, URI] URL of the file to download
    # @param insecure [Boolean] if true the SSL verification errors are ignored
    # @param redirection_count [Numeric] current redirection count, when zero
    #   the download fails with DownloadError exception
    # @return [String] the contents of the downloaded file
    def self.download_file(file_url, insecure: false, redirection_count: 10)
      if redirection_count < 0
        raise DownloadError,
          "Redirection not allowed or limit has been reached"
      end

      file_url = URI(file_url) unless file_url.is_a?(URI)
      http = Net::HTTP.new(file_url.host, file_url.port)

      if http.proxy?
        log.info "Reading proxy credentials..."
        http.proxy_user = SUSE::Toolkit::CurlrcDotfile.new.username
        http.proxy_pass = SUSE::Toolkit::CurlrcDotfile.new.password
      end

      # switch to HTTPS connection if needed
      if file_url.is_a? URI::HTTPS
        http.use_ssl = true
        http.verify_mode = insecure ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
        log.warn "Warning: SSL certificate verification disabled" if insecure
      else
        log.warn "Warning: Using insecure #{file_url.scheme.inspect} transfer protocol"
      end

      request = Net::HTTP::Get.new(file_url.request_uri)
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPRedirection
        location = response["location"]
        log.info "Redirected to #{location}"

        # retry recursively with redirected URL, decrease redirection counter
        download_file(location, insecure: insecure, redirection_count: redirection_count - 1)
      else
        log.error "HTTP request failed: Error #{response.code}:" \
          "#{response.message}: #{response.body}"

        raise DownloadError, "Downloading #{file_url} failed: #{response.message}"
      end
    end

    private_class_method :download_file
  end
end
