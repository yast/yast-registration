# Copyright (c) [2019] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "suse/connect"
require "registration/addon"
require "registration/remote_package"

module Registration
  # This class implements a packages search mechanism
  #
  # For the time being, it uses the SCC API to search for the wanted packages.
  #
  # @example Search for packages containing the `yast2` text in their names
  #   search = PackageSearch.new(text: "yast2")
  #   search.results.first #=> #<Registration::RemotePackage @name="autoyast2", ...>
  #
  # @example Case sensitive search
  class PackageSearch
    # @return [String] Text to search for
    attr_reader :text
    # @return [Boolean] Whether the search is case sensitive or not
    attr_reader :ignore_case

    # Constructor
    #
    # @param text        [String] Text to search for
    # @param ignore_case [Boolean] Whether the search is case sensitive or not
    def initialize(text:, ignore_case: true)
      @text = text
      @ignore_case = ignore_case
    end

    # Returns search results
    #
    # @return [Array<RemotePackage>] Packages search result
    def packages
      return @results if @results

      @results = find_packages(text).each_with_object([]) do |pkg, all|
        next unless ignore_case || pkg["name"].include?(text)

        remote_packages = pkg["products"].map do |product|
          RemotePackage.new(
            name:    pkg["name"],
            version: pkg["version"],
            release: pkg["release"],
            arch:    pkg["arch"],
            addon:   ::Registration::Addon.find_by_id(product["id"])
          )
        end
        all.concat(remote_packages)
      end
    end

  private

    def find_packages(text)
      ::FileUtils.mv("/var/run/zypp.pid", "/var/run/zypp.save") if File.exist?("/var/run/zypp.pid")
      SUSE::Connect::PackageSearch.search(text)
    ensure
      ::FileUtils.mv("/var/run/zypp.save", "/var/run/zypp.pid") if File.exist?("/var/run/zypp.save")
    end
  end
end
