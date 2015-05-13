
require "yast"
require "registration/addon"
require "registration/addon_sorter"

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

      # constructor
      # @param registration [Registration::Registration] use this Registration object for
      #   communication with SCC
      def initialize(registration)
        textdomain "registration"
        @addons = Addon.find_all(registration)

        # sort the addons
        @addons.sort!(&::Registration::ADDON_SORTER)

        @old_selection = Addon.selected.dup

        log.info "Available addons: #{@addons}"
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        raise "Not implented"
      end

      private

      def heading
        raise "Not implented"
      end

      def addon_selected?(_addon)
        raise "Not implented"
      end

      # create the main dialog definition
      # @return [Yast::Term] the main UI dialog term
      def content
        VBox(
          VStretch(),
          Left(Heading(heading)),
          addons_box,
          Left(Label(_("Details"))),
          MinHeight(8,
            VWeight(25, RichText(Id(:details), Opt(:disabled), "<small>" +
                  _("Select an extension or a module to show details here") + "</small>"))
          ),
          VStretch()
        )
      end

      # create UI box with addon check boxes, if the number of the addons is too big
      # the UI uses two column layout
      # @return [Yast::Term] the main UI dialog term
      def addons_box
        lines = Yast::UI.TextMode ? 9 : 14
        if @addons.size <= lines
          content = addon_selection_items(@addons)
        else
          box2 = addon_selection_items(@addons[lines..(2 * lines - 1)])
          box2.params << VStretch() # just UI tweak
          content = HBox(
            addon_selection_items(@addons[0..(lines - 1)]),
            HSpacing(1),
            box2
          )
        end

        VWeight(75, MarginBox(2, 1, content))
      end

      # create a single UI column with addon checkboxes
      # @return [Yast::Term] addon column
      def addon_selection_items(addons)
        box = VBox()

        # whether to add extra spacing in the UI
        if Yast::UI.TextMode
          add_extra_spacing = addons.size < 5
        else
          add_extra_spacing = true
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

        CheckBox(Id(addon.identifier), Opt(:notify), label, addon_selected?(addon))
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
            ret = Stage.initial && !Popup.ConfirmAbort(:painless) ? nil : :abort
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
      # @param id [String] addon identifier
      def handle_addon_selection(id)
        # check whether it's an add-on ID (checkbox clicked)
        addon = @addons.find { |a| a.identifier == id }
        return unless addon

        show_addon_details(addon)
        if Yast::UI.QueryWidget(Id(addon.identifier), :Value)
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
          Yast::UI.ChangeWidget(Id(addon.identifier), :Enabled, addon.selectable?)
        end
      end

      # the maximum number of reg. codes displayed vertically,
      # this is the limit for 80x25 textmode UI
      MAX_REGCODES_PER_COLUMN = 8

      # check the number of required reg. codes
      # @return [Boolean] true if the number of the required reg. codes fits
      #  the maximum limit
      def supported_addon_count?
        need_regcode = Addon.selected.reject(&:registered?).reject(&:free)
        # maximum number or reg codes which can be displayed in two column layout
        max_supported = 2 * MAX_REGCODES_PER_COLUMN

        # check the addons requiring a reg. code
        if need_regcode.size > max_supported
          Report.Error(_("YaST allows to select at most %s extensions or modules.") % max_supported)
          return false
        end

        true
      end
    end
  end
end
