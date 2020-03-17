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
    # Widget representing the button to toggle the status of a package
    class TogglePackageStatus < CWM::PushButton
      # @return [Registration::RemotePackage] the package
      attr_accessor :package

      # Constructor
      #
      # @param package [Registration::RemotePackage] the initial package
      def initialize(package = nil)
        textdomain "registration"

        @package = package
      end

      # Updates the button label and status
      def refresh
        Yast::UI.ChangeWidget(Id(widget_id), :Label, label)
        Yast::UI.ChangeWidget(Id(widget_id), :Enabled, enabled?)
      end

      # Returns button text based on the current package status
      #
      # @return [String] the buttons label
      def label
        return _("Select") unless package

        if package.installed?
          _("Installed")
        elsif package.selected?
          _("Unselect")
        else
          _("Select")
        end
      end

      # (see CWM::AbstractWidget#widget_id)
      def widget_id
        "toggle_package_status"
      end

      # (see CWM::AbstractWidget#opt)
      def opt
        opts = []
        opts << :disabled unless enabled?
        opts
      end

    private

      # Whether the button should be enabled or not
      #
      # @return [Boolean] true if there is a package and it isn't installed; false otherwise
      def enabled?
        return false unless package

        !package.installed?
      end
    end
  end
end
