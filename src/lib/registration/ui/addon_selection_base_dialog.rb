# Copyright (c) 2015 SUSE LINUX GmbH, Nuernberg, Germany.

require "yast"
require "registration/ui/abort_confirmation"
require "registration/addon"
require "registration/addon_sorter"
require "registration/sw_mgmt"

module Registration
  module UI
    # this class displays and runs the dialog with addon selection
    class AddonSelectionBaseDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Mode"
      Yast.import "GetInstArgs"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Stage"
      Yast.import "Arch"

      # constructor
      # @param registration [Registration::Registration] use this Registration object for
      #   communication with SCC
      def initialize(registration)
        textdomain "registration"
        @addons = Addon.find_all(registration)

        # sort the addons
        @addons.sort!(&::Registration::ADDON_SORTER)

        @old_selection = Addon.selected.dup

        # activate a workaround on ARM (FATE#320679)
        aarch64_workaround if Arch.aarch64

        log.info "Available addons: #{@addons}"
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

    private

      # reimplement this in a subclass
      # @return [String] dialog head
      def heading
        raise "Not implemented"
      end

      # reimplement this in a subclass
      # @return [Boolean] is the addon selected?
      def addon_selected?(_addon)
        raise "Not implemented"
      end

      # create the main dialog definition
      # @return [Yast::Term] the main UI dialog term
      def content
        VBox(
          VStretch(),
          Left(Heading(heading)),
          addons_box,
          Left(Label(_("Details"))),
          details_widget,
          VStretch()
        )
      end

      # addon description widget
      # @return [Yast::Term] the addon details widget
      def details_widget
        MinHeight(8,
          VWeight(25, RichText(Id(:details), Opt(:disabled), "<small>" +
                _("Select an extension or a module to show details here") + "</small>")))
      end

      # create UI box with addon check boxes, if the number of the addons is too big
      # the UI uses two column layout
      # @return [Yast::Term] the main UI dialog term
      def addons_box
        lines = Yast::UI.TextMode ? 9 : 14
        if @addons.size <= lines
          content = addon_selection_items(@addons)
        else
          content = two_column_layout(@addons[lines..(2 * lines - 1)], @addons[0..(lines - 1)])
        end

        VWeight(75, MarginBox(2, 1, content))
      end

      # display the addon checkboxes in two columns
      # @param col1 [Array<Addon>] the addons displayed in the first column
      # @param col2 [Array<Addon>] the addons displayed in the second column
      # @return [Yast::Term] the addon cheboxes
      def two_column_layout(col1, col2)
        box2 = addon_selection_items(col1)
        box2.params << VStretch() # just UI tweak

        HBox(
          addon_selection_items(col2),
          HSpacing(1),
          box2
        )
      end

      # create a single UI column with addon checkboxes
      # @return [Yast::Term] addon column
      def addon_selection_items(addons)
        box = VBox()

        # whether to add extra spacing in the UI
        add_extra_spacing = if Yast::UI.TextMode
          addons.size < 5
        else
          true
        end

        addons.each do |addon|
          box.params.concat(addon_checkbox(addon, add_extra_spacing))
        end

        box
      end

      # create spacing around the addon checkbox so the layout looks better
      # @param addon [Registration::Addon]
      # @param extra_spacing [Boolean] add extra spacing (indicates enough space in UI)
      # @return [Array<Yast::Term>] Return array with one or two elements for VBox
      def addon_checkbox(addon, extra_spacing)
        checkbox = Left(addon_checkbox_element(addon))

        # usability help. If addon depends on something, then we get it
        # immediatelly after parent, so indent it slightly, so it is easier visible
        checkbox = HBox(HSpacing(2.5), checkbox) if addon.depends_on

        res = [checkbox]
        # add extra spacing when there are just few addons, in GUI always
        res << VSpacing(0.7) if extra_spacing

        res
      end

      # create the UI checkbox element for the addon
      # @param addon [Registration::Addon] the addon
      # @return [Yast::Term] checkbox term
      def addon_checkbox_element(addon)
        # checkbox label for an unavailable extension
        # (%s is an extension name)
        label = addon.available? ? addon.label : (_("%s (not available)") % addon.label)

        CheckBox(Id(addon_widget_id(addon)), Opt(:notify), label, addon_selected?(addon))
      end

      # the main event loop - handle the user in put in the dialog
      # @return [Symbol] the user input
      def handle_dialog
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

        show_addon_details(addon)
        if Yast::UI.QueryWidget(Id(addon_widget_id(addon)), :Value)
          addon.selected
        else
          addon.unselected
        end
        reactivate_dependencies
      end

      # update addon details after changing the current addon in the UI
      # @param addon []
      def show_addon_details(addon)
        # addon description is a rich text
        Yast::UI.ChangeWidget(Id(:details), :Value, addon.description)
        Yast::UI.ChangeWidget(Id(:details), :Enabled, true)
      end

      # update the enabled/disabled status in UI for dependent addons
      def reactivate_dependencies
        @addons.each do |addon|
          Yast::UI.ChangeWidget(Id(addon_widget_id(addon)), :Enabled, addon.selectable?)
        end
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
          _("<p>If you want to remove any extension or module you need to log"\
              "into the SUSE Customer Center and remove them manually there.</p>")
      end

      # workaround for FATE#320679 - preselect the Toolchain module on ARM
      # in SLES12-SP2
      # FIXME: remove this hack in SLES12-SP3, use a proper solution instead
      def aarch64_workaround
        # SLES12-SP2 base?
        product = SwMgmt.base_product_to_register
        return unless product["name"] == "SLES" && product["version"] == "12.2"

        # is the Toolchain module available?
        toolchain = @addons.find do |addon|
          addon.identifier == "sle-module-toolchain" && addon.version == "12" \
            && addon.arch == "aarch64"
        end
        return unless toolchain

        # then pre-select it!
        log.info "Activating the ARM64 workaround, preselecting addon: #{toolchain}"
        toolchain.selected
      end
    end
  end
end
