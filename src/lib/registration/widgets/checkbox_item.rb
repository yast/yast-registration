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

module Registration
  module Widgets
    # A plain Ruby object in charge to build an item "checkbox" representation to be used by
    # {MasterDetailSelector} widget in a RichText widget.
    class CheckboxItem
      extend Yast::I18n

      textdomain "registration"

      # Map to icons used in GUI to represent all the known statuses in both scenarios, during
      # installation (`inst` mode) and in a running system (`normal` mode).
      #
      # Available statuses are
      #
      #   - `[ ]` not selected
      #   - `[x]` selected
      #   - `[a]` auto-selected
      IMAGES = {
        "inst:[a]:enabled"    => "auto-selected.svg",
        "inst:[x]:enabled"    => "inst_checkbox-on.svg",
        "inst:[x]:disabled"   => "inst_checkbox-on-disabled.svg",
        "inst:[ ]:enabled"    => "inst_checkbox-off.svg",
        "inst:[ ]:disabled"   => "inst_checkbox-off-disabled.svg",
        "normal:[a]:enabled"  => "auto-selected.svg",
        "normal:[x]:enabled"  => "checkbox-on.svg",
        "normal:[ ]:enabled"  => "checkbox-off.svg",
        # NOTE: Normal theme has no special images for disabled checkboxes
        "normal:[x]:disabled" => "checkbox-on.svg",
        "normal:[ ]:disabled" => "checkbox-off.svg"
      }.freeze
      private_constant :IMAGES

      # Path to the icons in the system
      IMAGES_DIR = "/usr/share/YaST2/theme/current/wizard".freeze
      private_constant :IMAGES_DIR

      # Help text
      #
      # @return [String]
      def self.help
        # TRANSLATORS: help text for checked check box
        checked     = _("Selected")
        # TRANSLATORS: help text for unchecked check box
        unchecked   = _("Not selected")
        # TRANSLATORS: help text for automatically checked check box (it has a different look that a
        # user selected check box)
        autochecked = _("Auto selected")

        help_text = []
        help_text << "<p>"
        help_text << "#{icon_for(:selected)} = #{checked}<br />"
        help_text << "#{icon_for(:auto_selected)} = #{autochecked}<br />"
        help_text << "#{icon_for(:deselected)} = #{unchecked}"
        help_text << "</p>"

        help_text.join
      end

      # Returns the icon to be used for an item with given status and state
      #
      # @see .value_for
      #
      # @param status [Symbol] the item status (e.g., :selected, :registered, :auto_selected)
      # @param mode [String] the running mode, "normal" or "inst"
      # @param state [String] the item state, "enabled" or "disabled"
      #
      # @return [String] an <img> tag when running in GUI mode; plain text otherwise
      def self.icon_for(status, mode: "normal", state: "enabled")
        value = value_for(status)

        if Yast::UI.TextMode
          value
        else
          # an image key looks like "inst:[a]:enabled"
          image_key = [mode, value, state].join(":")

          "<img src=\"#{IMAGES_DIR}/#{IMAGES[image_key]}\">"
        end
      end

      # Returns the status string representation
      #
      # @param status [Symbol]
      #
      # @return [String] the status text representation
      def self.value_for(status)
        case status
        when :selected, :registered
          "[x]"
        when :auto_selected
          "[a]"
        else
          "[ ]"
        end
      end

      # Constructor
      #
      # @param id [String, Integer] the representing the item
      # @param text [String] the text to be displayed
      # @param status [String, Symbol] the item status
      # @param enabled [Boolean] if the item should be enabled or not
      def initialize(id, text, status, enabled = true)
        @id = id
        @text = text
        @status = status
        @enabled = enabled
      end

      # Returns the checkbox representation for the item
      #
      # Basically, an string which contains two <a> tags, one for the input and other for the label
      #
      # @return [String] the richtext checkbox representation
      def to_s
        "#{checkbox} #{label}"
      end

    private

      attr_reader :id, :text, :status, :enabled

      # Builds the checkbox input representation
      #
      # @return [String]
      def checkbox
        if enabled
          "<a href=\"#{id}#checkbox#input\" style=\"#{text_style}\">#{icon}</a>"
        else
          "<span style\"#{text_style}\">#{icon}</a>"
        end
      end

      # @see .icon_for
      def icon
        self.class.icon_for(status, mode: mode, state: state)
      end

      # Builds the checkbox label representation
      #
      # @return [String]
      def label
        if enabled
          "<a href=\"#{id}#checkbox#label\" style=\"#{text_style}\">#{text}</a>"
        else
          "<span style\"#{text_style}\">#{text}</a>"
        end
      end

      # Returns the current mode
      #
      # @return [String] "normal" in a running system; "inst" during the installation
      def mode
        installation? ? "inst" : "normal"
      end

      # Returns the current input state
      #
      # @return [String] "enabled" when item must be enabled; "disabled" otherwise
      def state
        enabled ? "enabled" : "disabled"
      end

      # Returns style rules for the text
      #
      # @return [String] the status text representation
      def text_style
        "text-decoration: none; color: #{color}"
      end

      # Determines the color for the text
      #
      # @return [String] "grey" for a disabled item;
      #                  "white" when enabled and running in installation mode;
      #                  "black" otherwise
      def color
        return "grey" unless enabled
        return "white" if installation?

        "black"
      end

      # Determines whether running in installation mode
      #
      # We do not use Stage.initial because of firstboot, which runs in 'installation' mode
      # but in 'firstboot' stage.
      #
      # @return [Boolean] Boolean if running in installation or update mode
      def installation?
        Yast::Mode.installation || Yast::Mode.update
      end
    end
  end
end
