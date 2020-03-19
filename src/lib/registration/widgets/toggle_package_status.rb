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
      # Constructor
      def initialize
        textdomain "registration"
        self.widget_id = "toggle_package_status"
      end

      # Updates the button label and status
      #
      # @param package [Registration::RemotePackage, nil]
      def update(package)
        enabled = package ? !package.installed? : false

        Yast::UI.ChangeWidget(Id(widget_id), :Label, label_for(package))
        Yast::UI.ChangeWidget(Id(widget_id), :Enabled, enabled)

        # Ensures that label will be fully visible,
        # even after changing to a longer one
        Yast::UI::RecalcLayout()
      end

      # Determines the button label
      #
      # @return [String] the buttons label
      def label
        label_for(nil)
      end

      # (see CWM::AbstractWidget#opt)
      def opt
        [:disabled]
      end

    private

      # Returns the button text for given package
      #
      # @param package [Registration::RemotePackage, nil] the represented package, if any
      def label_for(package)
        return labels[:select] unless package

        key =
          if package.installed?
            :installed
          elsif package.selected?
            :unselect
          else
            :select
          end

        labels[key]
      end

      # Possible labels for the button
      #
      # @return [Hash<String>] all possible labels
      def labels
        @labels ||= {
          select:    _("Select"),
          unselect:  _("Unselect"),
          installed: _("Installed")
        }
      end
    end
  end
end
