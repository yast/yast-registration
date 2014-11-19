
require "yast"
require "registration/addon"
require "registration/addon_sorter"

module Registration
  module UI

    class AddonSelectionDialog
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

      # create a new dialog for accepting importing a SSL certificate and run it
      def self.run(registration)
        dialog = AddonSelectionDialog.new(registration)
        dialog.run
      end

      def initialize(registration)
        textdomain "registration"
        @addons = Addon.find_all(registration)

        # sort the addons
        @addons.sort!(&::Registration::ADDON_SORTER)

        log.info "Available addons: #{@addons}"
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        Wizard.SetContents(
          # dialog title
          _("Extension and Module Selection"),
          content,
          # help text (1/3)
          _("<p>Here you can select available extensions and modules for your"\
              "system.</p>") +
            # help text (2/3)
          _("<p>Please note, that some extensions or modules might need "\
              "specific registration code.</p>") +
            # help text (3/3)
          _("<p>If you want to remove any extension or module you need to log"\
              "into the SUSE Customer Center and remove them manually there.</p>"),
          # always enable Back/Next, the dialog cannot be the first in workflow
          true,
          true
        )

        @old_selection = Addon.selected.dup

        reactivate_dependencies

        handle_dialog
      end

      private

      def content
        VBox(
          VStretch(),
          Left(Heading(_("Available Extensions and Modules"))),
          addons_box,
          Left(Label(_("Details"))),
          MinHeight(8,
            VWeight(25, RichText(Id(:details), Opt(:disabled), "<small>" +
                  _("Select an extension or a module to show details here") + "</small>"))
          ),
          VStretch()
        )
      end

      def addons_box
        lines = Yast::UI.TextMode ? 9 : 14
        if @addons.size <= lines
          content = addon_selection_items(@addons)
        else
          box2 = addon_selection_items(@addons[lines..(2*lines - 1)])
          box2.params << VStretch() # just UI tweak
          content = HBox(
            addon_selection_items(@addons[0..(lines - 1)]),
            HSpacing(1),
            box2
          )
        end

        VWeight(75, MarginBox(2, 1, content))
      end

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

      # @return [Array] Return array with one or two elements for VBox
      def addon_checkbox(addon, extra_spacing)
        checkbox = Left(addon_checkbox_element(addon))

        # usability help. If addon depends on something, then we get it
        # immediatelly after parent, so indent it slightly, so it is easier visible
        if addon.depends_on
          checkbox = HBox(HSpacing(2.5), checkbox)
        end
        res = [checkbox]
        # add extra spacing when there are just few addons, in GUI always
        res << VSpacing(0.7) if extra_spacing

        return res
      end

      def addon_checkbox_element(addon)
        # checkbox label for an unavailable extension
        # (%s is an extension name)
        label = addon.available? ? addon.label : (_("%s (not available)") % addon.label)

        CheckBox(Id(addon.identifier),
          Opt(:notify),
          label,
          addon.selected? || addon.registered?)
      end

      def handle_dialog
        ret = nil
        continue_buttons = [:next, :back, :abort, :skip]

        while !continue_buttons.include?(ret) do
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

      def handle_next_button
        if !supported_addon_count?
          return nil
        end

        log.info "Selected addons: #{Addon.selected.map(&:name)}"

        Addon.selected.empty? ? :skip : :next
      end

      def handle_addon_selection(id)
        # check whether it's an add-on ID (checkbox clicked)
        addon = @addons.find{|addon| addon.identifier == id}
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
      def show_addon_details(addon)
        # addon description is a rich text
        Yast::UI.ChangeWidget(Id(:details), :Value, addon.description)
        Yast::UI.ChangeWidget(Id(:details), :Enabled, true)
      end

      def reactivate_dependencies
        @addons.each do |addon|
          Yast::UI.ChangeWidget(Id(addon.identifier), :Enabled, addon.selectable?)
        end
      end

      # the maximum number of reg. codes displayed vertically,
      # this is the limit for 80x25 textmode UI
      MAX_REGCODES_PER_COLUMN = 8

      # check for the maximum amount of reg. codes supported by Yast
      def supported_addon_count?
        need_regcode = Addon.selected.reject(&:registered?).reject(&:free)
        # maximum number or reg codes which can be displayed in two column layout
        max_supported = 2*MAX_REGCODES_PER_COLUMN

        # check the addons requiring a reg. code
        if need_regcode.size > max_supported
          Report.Error(_("YaST allows to select at most %s extensions or modules.") % max_supported)
          return false
        end

        return true
      end
    end
  end
end
