# Copyright (c) 2015 SUSE LINUX GmbH, Nuernberg, Germany.

require "yast"
require "registration/ui/abort_confirmation"
require "registration/addon"
require "registration/addon_sorter"
require "registration/sw_mgmt"
require "ui/text_helpers"

module Registration
  module UI
    # this class displays and runs the dialog with addon selection
    class AddonSelectionBaseDialog
      include ::UI::TextHelpers
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "GetInstArgs"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Stage"
      Yast.import "Arch"

      class << self
        attr_accessor :filter_devel
      end

      FILTER_DEVEL_INITIALLY = true

      # constructor
      # @param registration [Registration::Registration] use this Registration object for
      #   communication with SCC
      def initialize(registration)
        textdomain "registration"
        @all_addons = Addon.find_all(registration)

        # sort the addons
        @all_addons.sort!(&::Registration::ADDON_SORTER)

        self.class.filter_devel = FILTER_DEVEL_INITIALLY if self.class.filter_devel.nil?
        preselect_recommended
        filter_devel_releases(self.class.filter_devel)

        @old_selection = Addon.selected.dup
      end

      # reimplement this in a subclass
      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input
      def run
        raise "Not implemented"
      end

    protected

      # create widget ID for an addon
      # @param [<Addon>] addon the addon
      # @return [String] widget id
      def addon_widget_id(addon)
        "#{addon.identifier}-#{addon.version}-#{addon.arch}"
      end

      # Enables or disables devel addons filtering
      # @param [Boolean] enable true for filtering devel releases
      def filter_devel_releases(enable)
        self.class.filter_devel = enable
        if enable
          @addons = @all_addons.select do |a|
            a.registered? || a.selected? || a.auto_selected? ||
              a.released?
          end
        else
          @addons = @all_addons
        end
      end

    private

      # reimplement this in a subclass
      # @return [String] dialog head
      def heading
        raise "Not implemented"
      end

      # create the main dialog definition
      # @return [Yast::Term] the main UI dialog term
      def content
        elements = [title]
        elements << devel_filter if include_devel_filter?
        elements << addons_box

        VBox(*elements)
      end

      def title
        Left(Heading(heading))
      end

      def devel_filter
        checked = self.class.filter_devel.nil? ? FILTER_DEVEL_INITIALLY : self.class.filter_devel

        Left(
          # TRANSLATORS: Checkbox label, hides alpha or beta versions (not released yet)
          CheckBox( Id(:filter_devel), Opt(:notify), _("&Hide Development Versions"), checked)
        )
      end

      # Create the UI box with addon check boxes
      #
      # @return [Yast::Term] the main UI dialog term
      def addons_box
        # FIXME: the items will be added via UI.ChangeWidget; see #show_addons and
        # AddonSelectionRegistratioDialog#run
        content = CustomStatusItemSelector(Id(:items), Opt(:notify), custom_states, addons_items)

        content
      end

      # Build the items to be used by the addons selector
      #
      # @see #addons_box
      #
      # @return [Array<Yast::Term>] items for the addons selector.
      def addons_items
        @addons.map do |addon|
          label = addon.available? ? addon.label : (_("%s (not available)") % addon.label)
          # FIXME: move this sanitation to the wrap_text helper?
          description = addon.description.gsub("<br>", "\n").gsub("</p>", "\n\n").gsub("<p>", "").chomp

          # TODO: tell the addon status as 4th parameter, once Item supports non-boolean values
          Item(
            Id(addon_widget_id(addon)),
            addon.label,
            wrap_text(description, 110)
          )
        end
      end

      # Build the map of addons states
      #
      # @see #show_addons
      #
      # @return [Hash<String => Integer>]
      def addons_states
        @addons.reduce({}) do |states, addon|
          states[addon_widget_id(addon)] =
            case addon.status
            when :selected, :registered
              MOD_INSTALL
            when :auto_selected
              MOD_AUTOINSTALL
            else
              MOD_DONT_INSTALL
            end

          states
        end
      end

      MOD_DONT_INSTALL = 0
      private_constant :MOD_DONT_INSTALL
      MOD_INSTALL      = 1
      private_constant :MOD_INSTALL
      MOD_AUTOINSTALL  = 2
      private_constant :MOD_AUTOINSTALL

      def custom_states
        [
          # icon, NCurses indicator, next status (optional)
          ["checkbox-off",           "[ ]", MOD_INSTALL     ],
          ["checkbox-on",            "[x]", MOD_DONT_INSTALL],
          ["checkbox-auto-selected", "[a]", MOD_DONT_INSTALL]
        ]
      end

      # Whether the devel filter should be included or not
      #
      # @return [Boolean] true when there are not registered or released addons; false otherwise
      def include_devel_filter?
        !@all_addons.reject { |addon| addon.registered? || addon.released? }.empty?
      end

      # the main event loop - handle the user in put in the dialog
      # @return [Symbol] the user input
      def handle_dialog
        Yast::UI.SetFocus(Id(:items))

        ret = nil
        continue_buttons = [:next, :back, :abort, :skip]

        until continue_buttons.include?(ret)
          ret = Yast::UI.UserInput

          case ret
          when :next
            ret = handle_next_button
          when :cancel, :abort
            ret = Stage.initial && !AbortConfirmation.run ? nil : :abort
            # when canceled switch to old selection
            Addon.selected.replace(@old_selection) if ret == :abort
          when :filter_devel
            filter_devel_releases(Yast::UI.QueryWidget(Id(ret), :Value))
            show_addons
          else
            handle_addon_selection(ret)
          end
        end

        ret
      end

      # handler for the :next button in the main loop
      def handle_next_button
        return nil unless supported_addon_count?

        log.info "Selected addons: #{Addon.selected.map(&:name)}"

        Addon.selected.empty? ? :skip : :next
      end

      # handler for changing the addon status in the main loop
      # @param id [String] addon widget id
      def handle_addon_selection(id)
        # check whether it's an add-on ID (checkbox clicked)
        addon = @addons.find { |a| addon_widget_id(a) == id }
        return unless addon

        addon.toggle_selected
        show_addons
      end

      # Show the addon list
      #
      # Useful when items are added, filtered, enabled, disabled, selected, or unselected
      def show_addons
        Yast::UI.ChangeWidget(Id(:items), :Items, addons_items)
        Yast::UI.ChangeWidget(Id(:items), :ItemStatus, addons_states)
      end

      # the maximum number of reg. codes displayed vertically,
      # this is the limit for 80x25 textmode UI
      MAX_REGCODES_PER_COLUMN = 8

      # check the number of required reg. codes
      # @return [Boolean] true if the number of the required reg. codes fits
      #  the maximum limit
      def supported_addon_count?
        # maximum number or reg codes which can be displayed in two column layout
        max_supported = 2 * MAX_REGCODES_PER_COLUMN

        # check if the count of addons requiring a reg. code fits two columns
        if Addon.selected.count { |a| a.registered? && a.free } > max_supported
          Report.Error(_("YaST allows to select at most %s extensions or modules.") % max_supported)
          return false
        end

        true
      end

      # shared part of the help text
      # @return [String] translated help text
      def generic_help_text
        # help text (2/3)
        _("<p>Please note, that some extensions or modules might need "\
            "specific registration code.</p>") +
          # help text (3/3)
          _("<p>If you want to remove any extension or module you need to log "\
              "into the SUSE Customer Center and remove them manually there.</p>")
      end

      def preselect_recommended
        # something is already selected/registered, keep the user selection unchanged
        return if !Addon.selected.empty? || !Addon.registered.empty?

        @all_addons.each do |a|
          next unless a.recommended
          log.info("Preselecting a default addon: #{a.friendly_name}")
          a.selected
        end
      end
    end
  end
end
