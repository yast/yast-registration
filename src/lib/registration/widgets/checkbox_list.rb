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
    # A check boxes list intended to be the master widget in {MasterDetailSelector}
    class CheckboxList < CWM::RichText
      # Constructor
      #
      # @param initial_content [String] the content to be displayed after the first render
      def initialize(initial_content: "")
        @initial_content = initial_content
      end

      # @macro seeAbstractWidget
      def init
        self.value = initial_content
      end

      # @macro seeAbstractWidget
      def opt
        [:notify]
      end

      # Updates the widget's content
      #
      # FIXME: make optional the scroll restoration
      #
      # @param content [String] the content to be displayed
      def update(content)
        save_vscroll
        self.value = content
        restore_vscroll
      end

    private

      attr_reader :initial_content

      # Saves the current vertical scroll
      def save_vscroll
        @vscroll = Yast::UI.QueryWidget(Id(widget_id), :VScrollValue)
      end

      # Restores previously saved vertical scroll
      def restore_vscroll
        Yast::UI.ChangeWidget(Id(widget_id), :VScrollValue, @vscroll)
      end
    end
  end
end
