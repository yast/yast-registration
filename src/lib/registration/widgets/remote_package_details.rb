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
          format(_("<b>Name:</b> %{package_name}"), package_name: ERB::Util.h(package.name)),
          format(
            _("<b>Version:</b> %{package_version}"),
            package_version: ERB::Util.h(package.full_version)
          ),
          format(_("<b>Architecture:</b> %{package_arch}"), package_arch: ERB::Util.h(package.arch))
        ]

        if package.addon
          lines << format(
            _("<b>Module/Extension:</b> %{name} (%{status})"),
            name:   ERB::Util.h(package.addon.name),
            status: ERB::Util.h(addon_status(package.addon))
          )
        end

        self.value = lines.join("<br>")
      end

      # Clears the widget's content
      def clear
        self.value = ""
      end

    private

      # Displays the status of the given addon
      #
      # @param addon [Addon] Addon to display the status for
      # @return [String]
      def addon_status(addon)
        if addon.registered?
          # TRANSLATORS: module/extension status
          _("registered")
        elsif addon.selected?
          # TRANSLATORS: module/extension status (to be registered after confirmation)
          _("selected for registration")
        else
          # TRANSLATORS: module/extension status
          _("not registered")
        end
      end
    end
  end
end
