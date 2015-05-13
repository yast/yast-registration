
require "registration/ui/addon_selection_base_dialog"

module Registration
  module UI
    # this class displays and runs the dialog with addon selection
    class AddonSelectionReregistrationDialog < AddonSelectionBaseDialog
      # display and run the dialog with addon selection
      # @param registration [Registration::Registration] use this Registration object for
      #   communication with SCC
      # @return [Symbol] user input symbol
      def self.run(registration)
        dialog = AddonSelectionReregistrationDialog.new(registration)
        dialog.run
      end

      # constructor
      # @param registration [Registration::Registration] use this Registration object for
      #   communication with SCC
      def initialize(registration)
        super(registration)

        # filter out the unregistered addons
        @addons.select!(&:registered?)

        log.info "Registered addons: #{@addons}"
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        Wizard.SetContents(
          # dialog title
          _("Extension and Module Re-registration"),
          content,
          # help text (1/3)
          _("<p>Here you can select extensions and modules which will be "\
              "registered again.</p>") +
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

        handle_dialog
      end

      private

      # @return [String] the main dialog label
      def heading
        _("Registered Extensions and Modules")
      end

      def addon_selected?(addon)
        addon.selected?
      end

      # empty implementation, allow reregistration of a dependant addon
      # without reregistering its parent
      def reactivate_dependencies
      end
    end
  end
end
