# typed: false

require "yast"

module Registration
  module UI
    # this class displays and runs the status dialog for an already registered system
    class RegisteredSystemDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      attr_reader :addons

      Yast.import "Mode"
      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "UI"

      # displays and run the status dialog for an already registered system
      # @return [Symbol] user input
      def self.run
        dialog = RegisteredSystemDialog.new
        dialog.run
      end

      # the constructor
      def initialize
        textdomain "registration"
      end

      # display and run the dialog
      # @return [Symbol] user input
      def run
        Wizard.SetContents(
          # dialog title
          _("Registration"),
          dialog_content,
          # help text
          _("<p>The system is already registered.</p>") +
            _("<p>You can re-register it again or you can register additional "\
              "extension or modules to enhance the functionality of the system.</p>") +
            _("<p>If you want to deregister your system you need to log "\
              "into the SUSE Customer Center and remove the system manually there.</p>"),
          true,
          true
        )

        Wizard.SetNextButton(:next, Label.FinishButton) if Mode.normal

        continue_buttons = [:next, :back, :cancel, :abort, :register, :extensions]

        ret = nil
        ret = Yast::UI.UserInput until continue_buttons.include?(ret)

        Wizard.RestoreNextButton

        ret
      end

    private

      # the main dialog content
      # @return [Yast::Term] UI term
      def dialog_content
        VBox(
          Heading(_("The system is already registered.")),
          VSpacing(2),
          # button label
          PushButton(Id(:extensions), _("Select Extensions")),
          VSpacing(1),
          # button label
          PushButton(Id(:register), _("Register Again"))
        )
      end
    end
  end
end
