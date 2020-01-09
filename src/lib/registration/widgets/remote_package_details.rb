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
require "cwm/common_widgets"

module Registration
  module Widgets
    # This widgets displays the details of a remote package (name, arch, etc.)
    class RemotePackageDetails < CWM::RichText
      # Constructor
      def initialize
        textdomain("registration")
        super
      end

      # Updates the widget's content
      #
      # @param package [RemotePackage] Package obtained via online search
      def update(package)
        lines = [
          format(_("<b>Name:</b> %{package_name}"), package_name: package.name),
          format(_("<b>Version:</b> %{package_version}"), package_version: package.full_version),
          format(_("<b>Architecture:</b> %{package_arch}"), package_arch: package.arch)
        ]

        if package.addon
          lines.concat(
            [
              format(_("<b>Product:</b> %{name}"), name: package.addon.name),
              format(_("<b>Product Status:</b> %{status}"), status: addon_status(package.addon))
            ]
          )
        end

        self.value = lines.join("<br>")
      end

    private

      # Displays the status of the given addon
      #
      # @param addon [Addon] Addon to display the status for
      # @return [String]
      def addon_status(addon)
        if addon.registered?
          _("Registered")
        elsif addon.selected?
          _("To be registered")
        else
          _("Not registered")
        end
      end
    end
  end
end
