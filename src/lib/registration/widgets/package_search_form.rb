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
require "cwm/custom_widget"

module Registration
  module Widgets
    # Form to perform package searches
    #
    # It features two fields (term and case sensitiveness) and a search button to
    # start the query.
    class PackageSearchForm < ::CWM::CustomWidget
      def initialize
        textdomain "registration"
        super
      end

      def contents
        Frame(
          _("Search"),
          VBox(
            InputField(
              Id("search_form_text"), Opt(:hstretch, :notify, :immediate), _("Package Name")
            ),
            Left(CheckBox(Id("search_form_ignore_case"), _("Ignore Case"), true)),
            Right(PushButton(Id("search_form_button"), Opt(:default), _("Search")))
          )
        )
      end

      # Returns the text in the input field
      #
      # @return [String]
      def text
        Yast::UI.QueryWidget(Id("search_form_text"), :Value)
      end

      # Whether the search is case sensitive or not
      #
      # @return [Boolean]
      def ignore_case
        Yast::UI.QueryWidget(Id("search_form_ignore_case"), :Value)
      end
    end
  end
end
