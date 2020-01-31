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

require "yast"
require "registration/package_search"

Yast.import "Popup"

module Registration
  module Controllers
    # Implements the actions and keeps the state for the package search feature
    class PackageSearch
      # Returns the list of the current search
      #
      # @return [Array<RemotePackage>] List of found packages
      def packages
        @search ? @search.packages : []
      end

      # Performs a package search
      #
      # @param text [String] Term to search for
      def search(text)
        @search = ::Registration::PackageSearch.new(text: text)
        selected_package_ids = selected_packages.map(&:id)
        @search.packages.each do |pkg|
          pkg.select! if selected_package_ids.include?(pkg.id)
        end
      end
    end
  end
end
