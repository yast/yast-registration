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
    #
    # FIXME: give support for disabled items; see #icon
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
        "inst:[ ]:enabled"    => "inst_checkbox-off.svg",
        "inst:[x]disabled"    => "inst_checkbox-on-disabled.svg",
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

      # Returns the icon to be used for an item with given status
      #
      # @see #icon
      #
      # @return [String]
      def self.icon_for(status)
        new(nil, nil, status).icon
      end

      # Constructor
      #
      # @param id [String, Integer] the representing the item
      # @param text [String] the text to be displayed
      # @param status [String, Symbol] the item status
      def initialize(id, text, status)
        @id = id
        @text = text
        @status = status
      end

      # Returns the checkbox representation for the item
      #
      # Basically, an string which contains two <a> tags, one for the input and other for the label
      #
      # @return [String] the richtext checkbox representation
      def to_s
        "#{checkbox} #{label}"
      end

      # Builds the icon simulating a checkbox input
      #
      # @return [String] an <img> tag when running in GUI mode; plain text otherwise
      def icon
        if Yast::UI.TextMode
          value
        else
          # an image key looks like "inst:[a]:enabled"
          image_key = [mode, value, "enabled"].join(":")

          "<img src=\"#{IMAGES_DIR}/#{IMAGES[image_key]}\">"
        end
      end

    private

      attr_reader :id, :text, :status

      # Builds the checkbox input representation
      #
      # @return [String]
      def checkbox
        "<a href=\"#{id}#checkbox#input\" style=\"#{text_style}\">#{icon}</a>"
      end

      # Builds the checkbox label representation
      #
      # @return [String]
      def label
        "<a href=\"#{id}#checkbox#label\" style=\"#{text_style}\">#{text}</a>"
      end

      # Returns the status string representation
      #
      # In text mode it matches with the icon.
      #
      # @return [String] the status text representation
      def value
        case status
        when :selected, :registered
          "[x]"
        when :auto_selected
          "[a]"
        else
          "[ ]"
        end
      end

      # Returns style rules for the text
      #
      # @return [String] the status text representation
      def text_style
        "text-decoration: none; color: #{color}"
      end

      # Returns the current mode
      #
      # @return [String] "normal" in a running system; "inst" during the installation
      def mode
        installation? ? "inst" : "normal"
      end

      # Determines the color for the text
      #
      # @return [String] "black" in a running system; "white" during the isntallation
      def color
        installation? ? "white" : "black"
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
