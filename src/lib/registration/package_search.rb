# Copyright (c) [2020] SUSE LLC
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
require "y2packager/product"
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
    # @param product     [Y2Packager::Product] Base product to find the packages for. By default,
    #   it uses the installed base product.
    def initialize(text:, ignore_case: true, product: Y2Packager::Product.installed_base_product)
      @text = text
      @ignore_case = ignore_case
      @product = product
    end

    # Returns search results
    #
    # @return [Array<RemotePackage>] Packages search result
    def packages
      @packages ||= find_packages(text, product).each_with_object([]) do |pkg, all|
        next unless ignore_case || pkg["name"].include?(text)

        remote_packages = pkg["products"].map do |product|
          RemotePackage.new(
            id:      pkg["id"],
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

    attr_reader :product

    # Finds the packages using the SUSE/Connect package search feature
    #
    # @param text    [String] Query
    # @param product [Y2Packager::Product] Base product to find the packages for.
    # @return [Array<Hash>] Search results
    def find_packages(text, product)
      SUSE::Connect::PackageSearch.search(text, product: connect_product(product))
    end

    # Returns a SUSE::Connect::Zypper::Product instance to be used in the query
    #
    # @param yast_product [Y2Packager::Product] YaST's product representation
    # @return [SUSE::Connect::Zypper::Product]
    def connect_product(yast_product)
      SUSE::Connect::Zypper::Product.new(
        name:    yast_product.name,
        arch:    yast_product.arch.to_s,
        version: yast_product.version_version,
        isbase:  yast_product.category == :base,
        summary: yast_product.display_name
      )
    end
  end
end
