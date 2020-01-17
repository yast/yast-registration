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

      # @macro seeTable
      def items
        @items ||= []
      end

      # @macro seeAbstractWidget
      def opt
        [:notify, :immediate]
      end

      # @macro seeTable
      def header
        [_("Status"), _("Name"), _("Product")]
      end

      # @macro seeTable
      def change_items(items_list)
        @items = items_list
        super
      end

      # Returns the selected item
      #
      # @return [RemotePackage]
      def selected_item
        items.find { |i| i.name == value }
      end

    private

      # @see http://www.rubydoc.info/github/yast/yast-yast2/CWM%2FTable
      def format_items(items)
        items.map do |item|
          Item(
            Id(item.name),
            package_status(item),
            item.name,
            addon_column(item.addon)
          )
        end
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

      # Product status indicator
      #
      # @param addon [Addon] Addon to display the status for
      # @return [String]
      def addon_column(addon)
        format(
          # TRANSLATORS: product name and status
          _("%{product} (%{status})"),
          product: addon.name,
          status:  addon.status_to_human
        )
      end
    end
  end
end
