
require "yast"
require "registration/addon"
require "registration/helpers"

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

      # create a new dialog for accepting importing a SSL certificate and run it
      def self.run(registration)
        dialog = AddonEulaDialog.new(registration)
        dialog.run
      end

      # @param selected_addons
      def initialize(registration)
        textdomain "registration"
        @addons = Addon.find_all(registration)
      end

      # display the EULA for each dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        Wizard.SetContents(
          # dialog title
          _("Extension Selection"),
          content,
          # TODO FIXME: add a help text
          "",
          GetInstArgs.enable_back || Mode.normal, #FIXME make parameters
          GetInstArgs.enable_next || Mode.normal
        )

        @old_selection = Addon.selecteds.dup

        reactivate_depencies

        handle_dialog
      end

      private

      def content
        lines = UI.TextMode ? 9 : 14

        # use two column layout if needed
        vbox1 = addon_selection_items(addons[0..(lines - 1)])
        vbox2 = (addons.size > lines) ? HBox(
          HSpacing(1),
          VBox(
            addon_selection_items(addons[lines..(2*lines - 1)]),
            VStretch()
          )
        ) :
          Empty()

        VBox(
          VStretch(),
          Left(Heading(_("Available Extensions and Modules"))),
          VWeight(75, MarginBox(2, 1, HBox(
                vbox1,
                vbox2
              ))),
          Left(Label(_("Details"))),
          MinHeight(8,
            VWeight(25, RichText(Id(:details), Opt(:disabled), "<small>" +
                  _("Select an extension or a module to show details here") + "</small>")),
          ),
          VStretch()
        )
      end

      def addon_selection_items(addons)
        box = VBox()

        # whether to add extra spacing in the UI
        if UI.TextMode
          add_extra_spacing = addons.size < 5
        else
          add_extra_spacing = true
        end

        addons.each do |addon|
          label = addon.short_name
          label << " (#{addon.long_name})" if addon.long_name && !addon.long_name.empty?

          checkbox = Left(CheckBox(Id(addon.product_ident),
              Opt(:notify),
              addon.short_name,
              addon.selected? || addon.registered?))

          # usability help. If addon depends on something, then we get it
          # immediatelly after parent, so indent it slightly, so it is easier visible
          if addon.depends_on
            checkbox = HBox(HSpacing(0.5), checkbox)
          end
          box.params << checkbox
          # add extra spacing when there are just few addons, in GUI always
          box.params << VSpacing(0.7) if add_extra_spacing
        end

        box
      end

      def handle_dialog
        ret = nil
        continue_buttons = [:next, :back, :close, :abort, :skip]

        while !continue_buttons.include?(ret) do
          ret = UI.UserInput

          case ret
          when :next
            # ignore already registered addons
            to_register = Addon.selecteds.reject(&:registered?)

            if !supported_addon_count(to_register)
              ret = nil
              next
            end

            log.info "Selected addons: #{Addon.selecteds.map(&:short_name)}"

            ret = :skip if Addon.selecteds.empty?
          # when canceled switch to old selection
          when :close, :abort
            Addon.selecteds.replace(@old_selection)
          else
            # check whether it's an add-on ID (checkbox clicked)
            addon = addons.find{|addon| addon.product_ident == ret}

            # an addon has been changed, refresh details, check dependencies
            if addon
              show_addon_details(addon)
              if UI.QueryWidget(Id(addon.product_ident), :Value)
                addon.selected
              else
                addon.unselected
              end
              reactivate_depencies
            end
          end
        end

        ret
      end

      # update addon details after changing the current addon in the UI
      def show_addon_details(addon)
        # addon description is a rich text
        UI.ChangeWidget(Id(:details), :Value, addon.description)
        UI.ChangeWidget(Id(:details), :Enabled, true)
      end


      def reactivate_dependencies
        @addons.each do |addon|
          UI.ChangeWidget(Id(addon.product_ident), :Enabled, enable_addon?(addon))
        end
      end

      def enable_addon?(addon)
        # Do not support unregister
        return false if addon.registered?
        # Do not allow to select child without selected parent
        return false if addon.depends_on && !addon.depends_on.selected?
        # Do not allow to unselect parent if any children is selected
        return false if addon.children.any?(&:selected?)

        return true
      end

      # the maximum number of reg. codes displayed vertically,
      # this is the limit for 80x25 textmode UI
      MAX_REGCODES_PER_COLUMN = 9

      # check for the maximum amount of reg. codes supported by Yast
      def supported_addon_count(selected)
        # maximum number or reg codes which can be displayed in two column layout
        max_supported = 2*MAX_REGCODES_PER_COLUMN

        # check the addons requiring a reg. code
        if selected.count{|a| !a.free} > max_supported
          Report.Error(_("YaST allows to select at most %s addons.") % max_supported)
          return false
        end

        return true
      end
    end
  end
end

