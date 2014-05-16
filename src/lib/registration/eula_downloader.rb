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

  # class for downloading addon EULAs from the registration server
  class EulaDownloader
    attr_reader :base_url, :target_dir, :insecure

    include Yast::Logger

    # name of the directory index file with list of available files
    INDEX_FILE = "directory.yast"

    def initialize(base_url, target_dir, insecure: false)
      @base_url = base_url
      @target_dir = target_dir
      @insecure = insecure
    end

    # start the download
    def download
      licenses = available_licenses

      # download the files listed in the index
      licenses.each do |license|
        license_file_url = URI(base_url)
        license_file_url.path = File.join(license_file_url.path, license)

        log.info "Downloading license from #{license_file_url}..."
        license_text = download_file(license_file_url)
        log.info "Downloaded license: #{license_text[0..32].inspect}... (#{license_text.size} bytes)"

        license_file_name = File.join(target_dir, license)

        log.info "Saving the license to file: #{license_file_name}"
        File.write(license_file_name, license_text)
      end
    end

    private

    def download_file(file_url)
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

    # returns list of available files in a remote location
    def available_licenses
      # download the index file (directory.yast)
      index_url = URI(base_url)

      # add the index file to the URL path
      index_url.path = File.join(index_url.path, INDEX_FILE)

      # download the index
      log.info "Downloading license index from #{index_url}..."
      licenses = download_file(index_url).split

      # the index file itself might be also present in the list, just remove it
      licenses.delete(INDEX_FILE)
      log.info "Downloaded license index: #{licenses}"

      licenses
    end

  end


end