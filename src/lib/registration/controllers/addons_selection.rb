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
require "registration/addon"
require "registration/addon_sorter"

module Registration
  module Controllers
    # Controller to manage actions and state of addon selection
    #
    # Needed by {Widgets::MasterDetailSelector}
    class AddonsSelection
      include Yast::I18n

      class << self
        # @return [Boolean] If not released (e.g., alpha or beta versions) addons should be filtered
        attr_accessor :filtering_unreleased
      end

      # A checkbox item representation, see {Widgets::CheckboxItem}
      Item = Struct.new(:id, :label, :status, :description, :enabled)

      # Constructor
      #
      # It performs some necessary tasks
      #
      # * Sets the proper value for the filter, according to the last {.filtering_unreleased} value.
      # * Saves a copy of currently selected addons, to restore them if needed.
      # * Pre-selects recommended addons if proceed.
      #
      # @param registration [Registration::Registration] object allowing communication with SCC
      def initialize(registration)
        textdomain "registration"

        # initialize filter
        self.class.filtering_unreleased = true if filter.nil?

        @available_addons = Addon.find_all(registration).sort(&::Registration::ADDON_SORTER)
        @initial_addons_selection = Addon.selected.dup
        preselect_recommended
      end

      # Returns a collection of {Item} representing available addons
      #
      # @see #item_for
      #
      # @return [Array<Item>]
      def items
        addons.map { |addon| item_for(addon) }
      end

      # Returns the Item matching with given id, if any
      #
      # @param id [String]
      # @return [Item, nil]
      def find_item(id)
        addon = find_addon(id)

        return unless addon

        item_for(addon)
      end

      # Toggles the selection status for the addon represented by given item
      #
      # @param item [Item]
      def toggle_item_selection(item)
        addon = find_addon(item.id)
        addon && addon.toggle_selected
      end

      # Returns a collection holding selected addons
      #
      # @see Addon.selected
      #
      # @return [Array<Addon>]
      def selected_items
        selected_addons = Addon.selected

        log.info "Selected addons: #{selected_addons.map(&:name)}"

        selected_addons
      end

      # Restores selected addons to the initial selection
      #
      # @see @initial_addons_selection
      def restore_selection
        Addon.selected.replace(initial_addons_selection)
      end

      # Returns options for the master widget
      #
      # @see Widgets::MasterDetailSelector
      #
      # @return [Hash]
      def master_options
        {}
      end

      # Returns options for the details widget
      #
      # @see Widgets::MasterDetailSelector
      #
      # @return [Hash]
      def detail_options
        {
          placeholder: _("Select an extension or a module to show details here")
        }
      end

      # Whether {Widgets::MasterDetailSelector} should include a filter option
      #
      # @see Widgets::MasterDetailSelector
      # @see #development_addons
      #
      # @return [Boolean] true if there is any development; false otherwise
      def include_filter?
        !development_addons.empty?
      end

      # Whether {Widgets::MasterDetailSelector} should include a filter option
      #
      # @see Widgets::MasterDetailSelector
      # @see #development_addons
      #
      # @return [Boolean] true if there is any development; false otherwise
      def filter_label
        _("&Hide Development Versions")
      end

      # Returns the current value for the filter
      #
      # @see .filtering_unreleased
      #
      # @return [Boolean] true if filter is active; false otherwise
      def filter
        self.class.filtering_unreleased
      end

      # Updates the filter value
      #
      # @param enabled [Boolean] the new value for the filter
      def filter=(enabled)
        self.class.filtering_unreleased = enabled
      end

      # FIXME: still relevant?
      #
      # Max number of registration codes that can be displayed vertically in an 80x25 ncurses UI
      MAX_REGCODES_PER_COLUMN = 8
      private_constant :MAX_REGCODES_PER_COLUMN

      # Whether the number of required registration codes are withing the limit
      #
      # @return [Boolean] true if number of the required registration codes fits the maximum limit
      def supported_addon_count?
        # Maximum number or reg codes which can be displayed in two column layout
        max_supported = 2 * MAX_REGCODES_PER_COLUMN
        # Addons requiring a registration code
        requiring_reg_codes = Addon.selected.count { |a| a.registered? && a.free }

        if requiring_reg_codes > max_supported
          Report.Error(_("YaST allows to select at most %s extensions or modules.") % max_supported)
          return false
        end

        true
      end

    private

      # @return [Array<Addon>] List of available addons
      attr_reader :available_addons

      # @return [Array<Addon>] List of initially selected addons
      attr_reader :initial_addons_selection

      # Returns the addon representation as is expected by {Widgets::CheckboxItem}
      #
      # @return [Item]
      def item_for(addon)
        Item.new(
          item_id_for(addon),
          item_label_for(addon),
          addon.status,
          "<h3>#{addon.friendly_name}</h3>#{addon.description}",
          # the item will be enabled if the addon is selected, auto-selected or available
          addon.selected? || addon.auto_selected? || addon.available?
        )
      end

      # Returns the available addons based in the filter status
      #
      # When filtering, developments addons will be rejected unless the are selected or
      # auto-selected.
      #
      # @return [Array<Addon>] all addons if filter is not active; filtered collection otherwise
      def addons
        if filter
          available_addons.select do |addon|
            addon.registered? || addon.selected? || addon.auto_selected? || addon.released?
          end
        else
          available_addons
        end
      end

      # Returns development addons that are NOT registered yet
      #
      # @return [Array<Addon>] not registered development addons.
      def development_addons
        available_addons.reject { |addon| addon.registered? || addon.released? }
      end

      # Looks for an addon by given item id
      #
      # @see #item_id_for
      #
      # @param id [String] an Item id
      def find_addon(id)
        available_addons.find { |addon| item_id_for(addon) == id }
      end

      # Builds the Item id based on the addon information
      #
      # @return [String] an Item id
      def item_id_for(addon)
        "#{addon.identifier}-#{addon.version}-#{addon.arch}"
      end

      # Build the Item label based on the addon availability
      #
      # @return [String] the addon label with the "not available" suffix when proceed
      def item_label_for(addon)
        if addon.available?
          addon.label
        else
          _("%s (not available)") % addon.label
        end
      end

      # Pre-selects recommended addons if there is none selected/registered yet
      def preselect_recommended
        if Addon.selected.empty? && Addon.registered.empty?
          available_addons.each do |a|
            next unless a.recommended
            log.info("Preselecting a default addon: #{a.friendly_name}")
            a.selected
          end
        end
      end
    end
  end
end
