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
    # Widget representing the button to toggle package selection status
    class TogglePackageSelection < CWM::PushButton
      # Constructor
      def initialize
        super
        textdomain "registration"
        self.widget_id = "toggle_package_selection"
      end

      # Updates the button state according to the given value
      #
      # @param value [Boolean] if the button should be enabled or not
      def enabled=(value)
        Yast::UI.ChangeWidget(Id(widget_id), :Enabled, value)
      end

      # Returns the button text
      #
      # @return [String] the button text
      def label
        # TRANSLATORS: the text for the button to toggle the package selection
        _("Toggle selection")
      end

      # (see CWM::AbstractWidget#opt)
      def opt
        [:disabled]
      end
    end
  end
end
