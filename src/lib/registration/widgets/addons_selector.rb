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
require "forwardable"
require "cwm/multi_status_selector"

module Registration
  module Widgets
    # The addons multi selector widget, capable to deal with both
    #
    #   - the state (enable or disable)
    #   - the status (selected/registered, not selected, or auto selected)
    #
    # @see CWM::MultiStatusSelector
    class AddonsSelector < CWM::MultiStatusSelector
      include Yast::Logger
      include Yast::UIShortcuts
      include Yast::I18n

      class << self
        # @return [Boolean] When not released addons (i.e., alpha or beta versions) can be shown
        attr_accessor :release_only
      end

      # Constructor
      #
      # @param addons [Array<Addon>] an addons collection
      def initialize(addons)
        textdomain "registration"

        @items = addons.map { |addon| Item.new(addon) }
        self.class.release_only = true if self.class.release_only.nil?
      end

      def init
        super

        # Emulates the same behavior than yast2-packager >= 4.2.55
        details_widget.value = default_details
      end

      # @macro seeAbstractWidget
      def contents
        VBox(
          Left(filter_widget),
          VWeight(60, super),
          VWeight(
            40,
            VBox(
              Left(Label(_("Details (English only)"))),
              details_widget
            )
          )
        )
      end

      # @macro seeAbstractWidget
      def handle(event)
        super

        if show_filter? && event["ID"] == filter_widget.widget_id
          self.class.release_only = filter_widget.checked?

          refresh
          details_widget.value = default_details
        end

        nil
      end

      # Returns a collection of {Item} representing available addons
      #
      # Depending on {.release_only}, the collection will include unreleased and not (auto)selected
      # or registered items.
      #
      # @return [Array<Item>]
      def items
        if self.class.release_only
          # When filtering, not already selected or auto-selected developments addons will be hidden
          @items.select(&:visible?)
        else
          @items
        end
      end

      # @macro seeAbstractWidget
      def help
        Item.help
      end

    private

      # Returns the details to be shown by default
      #
      # To be used mainly during the initialization or after toggling the filter.
      #
      # @return [String] the first item description or an empty string if none
      def default_details
        items.first ? items.first.description : ""
      end

      # (see CWM::MultiStatusSelector#input_event_handler)
      def input_event_handler(item)
        super
        # FIXME: only if item get selected?
        label_event_handler(item)
      end

      # (see CWM::MultiStatusSelector#label_event_handler)
      def label_event_handler(item)
        details_widget.value = item.description
      end

      # Whether the filter must be shown
      #
      # @return [Boolean] true if there are any registered or released item; false otherwise
      def show_filter?
        @show_filter ||= @items.reject(&:registered_or_released?).any?
      end

      # Widget to display the filter, when needed
      #
      # @return [Filter, Yast::Term] Filter if the filter should be displayed; Empty otherwise
      def filter_widget
        @filter_widget ||= show_filter? ? Filter.new(self.class.release_only) : Empty()
      end

      # Widget to display the details area
      #
      # @return [CWM::RichText]
      def details_widget
        @details_widget ||=
          begin
            w = CWM::RichText.new
            w.widget_id = "details_area"
            w
          end
      end

      # Convenience widget to build the filter
      class Filter < CWM::CheckBox
        # Constructor
        #
        # @param value [Boolean] the initial value
        def initialize(value)
          @initial = value
        end

        # @macro seeAbstractWidget
        def init
          self.value = @initial
        end

        # @macro seeAbstractWidget
        def label
          # TRANSLATORS: check box label
          _("&Hide Development Versions")
        end

        # @macro seeAbstractWidget
        def opt
          [:notify]
        end
      end

      # Internal class to represent an {Registration::Addon} as selectable item
      #
      # @note The addon status is directly managed by {Registration::Addon}. See delegated methods.
      class Item < Item
        extend Forwardable
        include Yast::I18n

        # Constructor
        #
        # @param addon [Registration::Addon] the addon to be represented
        def initialize(addon)
          textdomain "registration"

          @addon = addon
        end

        # @!method toggle
        #   Toggles the item
        #   @note the logic to toggle an addon status is actually delegated to {Registration::Addon}
        def_delegator :@addon, :toggle_selected, :toggle

        # @!method enabled?
        #   @return [Boolean] true if the addon is available; false when not.
        def_delegator :@addon, :available?, :enabled?

        # @!method description
        #   @return [String] the item description, using richtext
        def_delegators :@addon, :description

        def id
          @id ||= "#{addon.identifier}-#{addon.version}-#{addon.arch}"
        end

        # Builds and return the item label based on the addon label and availability
        #
        # @return [String] the item label
        def label
          @label ||=
            if addon.available?
              addon.label
            else
              # TRANSLATORS: label for a not available module/extension, %s is replaced by the
              # module/extension name
              _("%s (not available)") % addon.label
            end
        end

        # Whether an item should be visible even when filtering development items out
        #
        # @return [Boolean] true if (auto)selected, released or already registered; false otherwise
        def visible?
          registered_or_released? || addon.selected? || addon.auto_selected?
        end

        # Whether the item should be considered as released or already registered
        #
        # @return [Boolean] true when released or already registered; false otherwise
        def registered_or_released?
          addon.registered? || addon.released?
        end

        # Returns the item status
        #
        # Since the addon status is completely handle by the {Registration::Addon}, this method
        # simply makes the conversion to a valid item status. Thus, registered addon will be
        # presented as selected item.
        #
        # @return [Symbol] the item status
        def status
          case addon.status
          when :selected, :registered
            SELECTED
          when :auto_selected
            AUTO_SELECTED
          else
            UNSELECTED
          end
        end

      private

        attr_reader :addon
      end
    end
  end
end
