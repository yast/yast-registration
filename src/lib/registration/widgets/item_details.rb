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
    # A CWM::RictText intended to be the widget to display item details in {MasterDetailSelector}
    class ItemDetails < CWM::RichText
      # Constructor
      #
      # @param placeholder [String] the placeholder to be shown as initial content
      def initialize(placeholder: nil)
        @placeholder = placeholder || ""
      end

      # @macro seeAbstractWidget
      def init
        self.value = placeholder
      end

      # @macro seeAbstractWidget
      def opt
        [:disabled]
      end

      # Updates the widget's content
      #
      # @param content [String] the content to be displayed
      def update(content)
        self.value = content
      end

      # Disables  the widget and resets its content
      def reset
        disable
        self.value = placeholder
      end

    private

      # @return [String] the placeholder to be shown as initial content
      attr_reader :placeholder
    end
  end
end
