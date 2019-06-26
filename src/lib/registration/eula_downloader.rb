# typed: true
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

require "registration/downloader"

module Registration
  # class for downloading addon EULAs from the registration server
  class EulaDownloader
    attr_reader :base_url, :target_dir, :insecure

    include Yast::Logger

    # name of the directory index file with list of available files
    INDEX_FILE = "directory.yast".freeze

    # the constructor
    # @param base_url [String] the base URL for EULAs
    # @param target_dir [String] where to save the downloaded files
    # @param insecure [Boolean] if true the SSL verification errors are ignored
    def initialize(base_url, target_dir, insecure: false)
      @base_url = base_url
      @target_dir = target_dir
      @insecure = insecure
    end

    # start the download, downloads the EULAS to the target directory
    def download
      licenses = available_licenses

      # download the files listed in the index
      licenses.each do |license|
        license_file_url = URI(base_url)
        license_file_url.path = File.join(license_file_url.path, license)

        log.info "Downloading license from #{license_file_url}..."
        license_text = Downloader.download(license_file_url, insecure: insecure)
        log.info "Downloaded license: #{license_text[0..32].inspect}... " \
          "(#{license_text.bytesize} bytes)"

        license_file_name = File.join(target_dir, license)

        log.info "Saving the license to file: #{license_file_name}"
        File.write(license_file_name, license_text)
      end
    end

  private

    # returns list of available files in a remote location
    # @return [Array<String>] the list of the remote EULAs
    def available_licenses
      # download the index file (directory.yast)
      index_url = URI(base_url)

      # add the index file to the URL path
      index_url.path = File.join(index_url.path, INDEX_FILE)

      # download the index
      log.info "Downloading license index from #{index_url}..."
      licenses = Downloader.download(index_url, insecure: insecure).split

      # the index file itself might be also present in the list, just remove it
      licenses.delete(INDEX_FILE)
      log.info "Downloaded license index: #{licenses}"

      licenses
    end
  end
end
