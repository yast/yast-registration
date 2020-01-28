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
require "cwm/table"

module Registration
  module Widgets
    # This widgets displays a list of remote packages
    #
    # The listing includes the related product information too.
    class RemotePackagesTable < CWM::Table
      # Constructor
      def initialize
        textdomain "registration"
        self.widget_id = "remote_packages_table"
        super
      end

      # @macro seeAbstractWidget
      def opt
        [:notify, :immediate, :keepSorting]
      end

      # @macro seeTable
      def header
        [
          Center(
            # TRANSLATORS: package status (installed, selected, etc.)
            _("Status")
          ),
          # TRANSLATORS: package name
          _("Name"),
          # TRANSLATORS: module or extension name
          _("Module/Extension")
        ]
      end

      # Updates the information for the given package
      #
      # @param item [RemotePackage] Package to update
      def update_item(item)
        columns_for_item(item).each_with_index do |content, idx|
          change_cell(Id(item.id), idx, content)
        end
      end

    private

      # @see https://www.rubydoc.info/github/yast/yast-yast2/CWM%2FTable
      def format_items(items)
        items.map do |item|
          columns = [Id(item.id)] + columns_for_item(item)
          Item(*columns)
        end
      end

      # Returns the content for the given item
      #
      # @param item [RemotePackage]
      def columns_for_item(item)
        [
          package_status(item),
          item.name,
          item.addon ? item.addon.name : ""
        ]
      end

      # Package status indicator
      #
      # @param package [RemotePackage] Package to display the status for
      # @return [String]
      def package_status(package)
        if package.installed?
          Yast::UI.Glyph(:CheckMark)
        elsif package.selected?
          "+"
        else
          ""
        end
      end
    end
  end
end
