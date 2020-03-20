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
      #
      # @param package [Registration::RemotePackage, nil]
      def initialize(package = nil)
        textdomain "registration"
        self.widget_id = "toggle_package_status"

        @package = package
      end

      # Determines the button label
      #
      # @return [String] the buttons label
      def label
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

      # (see CWM::AbstractWidget#opt)
      def opt
        opts = []
        opts << :disabled if !package || package.installed?
        opts
      end

    private

      attr_reader :package

      # Possible labels for the button
      #
      # @return [Hash<String>] all possible labels
      def labels
        @labels ||= {
          # TRANSLATORS: the button text for the "Select" package action
          select:    _("Select package"),
          # TRANSLATORS: the button text for the "Unselect" package action
          unselect:  _("Unselect package"),
          # TRANSLATORS: the button text when the selected package is already installed
          installed: _("Already installed")
        }
      end
    end
  end
end
