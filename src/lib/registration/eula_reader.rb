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

require "registration/helpers"

module Registration
  # class for loading addon EULA translation mapping from a directory,
  # the licenses attribute contains translations mapping { <locale> => <file_name> }
  class EulaReader
    attr_reader :base_dir, :licenses

    include Yast::Logger

    def initialize(base_dir)
      @base_dir = base_dir
      read_licenses
    end

    # Get the EULA translation to display. Selects the most suitable language
    # from the available translations according to the current locale setting.
    # @return [String] a language name
    def current_language
      current_language = Helpers.current_language || "en_US"

      # exact match
      return current_language if licenses[current_language]

      # try partial match, remove the country suffix
      current_language = remove_country_suffix(current_language)
      return current_language if licenses[current_language]

      # find a fallback if no translation was found
      fallback_language
    end

    def languages
      licenses.keys
    end

    private

    # read downloaded EULAs
    # @param dir [String] directory with EULA files
    def read_licenses
      @licenses = {}
      Dir["#{base_dir}/license.*"].each { |license| add_license_file(license) }
      log.info "EULA files in #{base_dir}: #{licenses}"
    end

    # add a license file mapping for this file
    # @param [String] license_file license file name
    def add_license_file(license_file)
      file = File.basename(license_file)

      case file
      when "license.txt"
        @licenses["en_US"] ||= license_file
      when /\Alicense\.(.*)\.txt\z/
        @licenses[Regexp.last_match[1]] = license_file
      else
        log.warn "Ignoring unknown file: #{file}"
      end
    end

    # find a fallback language
    def fallback_language
      # use English fallback when present
      return "en_US" if languages.include?("en_US")
      return "en" if languages.include?("en")

      # we cannot find any suitable language, just pick any from the list
      # (return the first item from alphabetically sorted list to have
      # consistent results and not to be completely random)
      languages.sort.first
    end

    # helper for removing the country suffix, e.g. "de_DE" => "de"
    # @param code [String] input locale name
    # @return [String] result locale name
    def remove_country_suffix(code)
      code.sub(/_.*\z/, "")
    end
  end
end
