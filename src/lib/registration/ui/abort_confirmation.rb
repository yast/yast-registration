require "yast"

module Registration
  module UI
    # this class displays a popup for the user to confirm the abort
    class AbortConfirmation
      include Yast::I18n

      Yast.import "Popup"
      Yast.import "Mode"
      Yast.import "Label"

      # displays a new popup
      # @return [Boolean] true whether the user confirmed he/she wants to abort
      def self.run
        dialog = new
        dialog.run
      end

      # the constructor
      def initialize
        textdomain "registration"
      end

      # displays the popup
      # @return [Boolean] true whether the user confirmed he/she wants to abort
      def run
        if Yast::Mode.installation
          Yast::Popup.ConfirmAbort(:painless)
        else
          # Use .AnyQuestion instead of .YesNo or .ReallyAbort to have full control
          # on :focus_no and be consistent with the .ConfirmAbort behavior
          Yast::Popup.AnyQuestion(
            Yast::Popup::NoHeadline(),
            _("Really abort?"),
            Yast::Label.YesButton,
            Yast::Label.NoButton,
            :focus_no
          )
        end
      end
    end
  end
end
