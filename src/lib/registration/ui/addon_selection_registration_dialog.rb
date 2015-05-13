
require "registration/ui/addon_selection_base_dialog"

module Registration
  module UI
    # this class displays and runs the dialog with addon selection
    class AddonSelectionRegistrationDialog < AddonSelectionBaseDialog
      # display and run the dialog with addon selection
      # @param registration [Registration::Registration] use this Registration object for
      #   communication with SCC
      # @return [Symbol] user input symbol
      def self.run(registration)
        dialog = AddonSelectionRegistrationDialog.new(registration)
        dialog.run
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

      # @return [String] the main dialog label
      def heading
        _("Available Extensions and Modules")
      end

      # update the enabled/disabled status in UI for dependent addons
      def reactivate_dependencies
        @addons.each do |addon|
          Yast::UI.ChangeWidget(Id(addon.identifier), :Enabled, addon.selectable?)
        end
      end
    end
  end
end
