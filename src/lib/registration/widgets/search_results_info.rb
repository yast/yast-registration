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
require "cwm/custom_widget"

module Registration
  module Widgets
    # Widget to display information about the search results
    class SearchResultsInfo < CWM::CustomWidget
      # Constructor
      def initialize
        textdomain "registration"
      end

      # (see CWM::CustomWidget#contents)
      def contents
        Label(label_id, initial_text)
      end

      # Updates the information shown based in found results
      #
      # @param results [Integer] the amount of packages found
      def update(results)
        text =
          if results.zero?
            _("No packages found")
          else
            n_("%s package found", "%s packages found", results) % results
          end

        Yast::UI.ChangeWidget(label_id, :Value, text)
      end

    private

      # Returns the id for the label
      #
      # @return [Yast::Term] the id for the label
      def label_id
        @label_id ||= Id(:search_results_info)
      end

      # Returns the text used the first time
      #
      # @return [String] the text to display initially
      def initial_text
        _("Not results yet")
      end
    end
  end
end
