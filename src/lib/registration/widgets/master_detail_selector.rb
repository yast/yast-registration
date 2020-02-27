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
require "registration/widgets/checkbox_list"
require "registration/widgets/checkbox_item"
require "registration/widgets/item_details"

module Registration
  module Widgets
    # A custom widget displaying a multi selection list in a master-detail interface
    #
    # It relies  on two child CWM::RichText widgets to show the list of selectable items (master) on
    # top and the description (detail) for one of them at bottom.
    #
    # A controller is needed to manage the communication between all the pieces and keeps the
    # selection logic and some configuration details such as the aspect relation or the availability
    # of a filter. See {Registration::Controllers::AddonsSelection}
    class MasterDetailSelector < CWM::CustomWidget
      include Yast::Logger
      include Yast::UIShortcuts

      DEFAULT_MASTER_VWEIGHT = 60
      private_constant :DEFAULT_MASTER_VWEIGHT

      DEFAULT_DETAIL_VWEIGHT = 40
      private_constant :DEFAULT_DETAIL_VWEIGHT

      # Constructor
      #
      # @param controller [Registration::Controller::AddonsSelection]
      def initialize(controller)
        self.handle_all_events = true

        @controller = controller

        super()
      end

      # @macro seeAbstractWidget
      def contents
        VBox(
          Left(filter),
          master_content,
          detail_content
        )
      end

      # @macro seeAbstractWidget
      def handle(event)
        case event["ID"]
        when :filter
          controller.filter = Yast::UI.QueryWidget(Id(:filter), :Value)

          # Reset the details box
          item_details_widget.reset

          # Refresh the list
          checkbox_list_widget.update(checkbox_list_items)
        when /#checkbox#/
          id, click_on = event["ID"].split("#checkbox#")

          item = controller.find_item(id)

          # FIXME: this is not expected, but...
          return unless item

          # Show details
          item_details_widget.enable
          item_details_widget.update(item.description)

          # All done if the user clicked on label
          return if click_on == "label"

          # Toggle selection
          controller.toggle_item_selection(item)

          # Refresh the list
          checkbox_list_widget.update(checkbox_list_items)
        end

        nil
      end

      # @macro seeAbstractWidget
      def help
        CheckboxItem.help
      end

    private

      attr_reader :controller

      # Widget representing the filter when needed
      #
      # @return [Yast::Term] CheckBox if the filter should be included; Empty otherwise
      def filter
        return Empty() unless controller.include_filter?

        CheckBox(Id(:filter), Opt(:notify), controller.filter_label, controller.filter)
      end

      # Returns the Yast::Term to fill the master area
      #
      # @return [Yast::Term]
      def master_content
        vweight = controller.master_options.fetch(:vweight, DEFAULT_MASTER_VWEIGHT)

        VWeight(
          vweight,
          checkbox_list_widget
        )
      end

      # Returns the Yast::Term to fill the detail area
      #
      # @return [Yast::Term]
      def detail_content
        vweight = controller.detail_options.fetch(:vweight, DEFAULT_DETAIL_VWEIGHT)

        VWeight(
          vweight,
          item_details_widget
        )
      end

      # Returns the widget to hold the selection list
      #
      # @return [Widgets::CheckboxList]
      def checkbox_list_widget
        @checkbox_list_widget ||=
          CheckboxList.new(initial_content: checkbox_list_items)
      end

      # Returns the widget to display an item details
      #
      # @return [Widgets::ItemDetails]
      def item_details_widget
        @item_details_widget ||=
          ItemDetails.new(placeholder: controller.detail_options[:placeholder])
      end

      # Builds the checkbox list
      #
      # @return [String]
      def checkbox_list_items
        separator = Yast::UI.TextMode ? "<br />" : ""

        checkboxes = controller.items.map do |item|
          item = CheckboxItem.new(item.id, item.label, item.status, item.enabled)
          item = "<p>#{item}</p>" unless Yast::UI.TextMode
          item
        end

        checkboxes.join(separator)
      end
    end
  end
end
