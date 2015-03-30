
require "yast"
require "registration/helpers"

module Registration
  module UI
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

      # create a new dialog for accepting importing a SSL certificate and run it
      def self.run
        dialog = RegisteredSystemDialog.new
        dialog.run
      end

      def initialize
        textdomain "registration"
      end

      # display the EULA for each dialog and wait for a button click
      # @return [Symbol] user input (:next, :back, :abort, :halt)
      def run
        log.info "The system is already registered, displaying registered dialog"

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
          GetInstArgs.enable_back || Mode.normal,
          GetInstArgs.enable_back || Mode.normal
        )

        Wizard.SetNextButton(:next, Label.FinishButton) if Mode.normal

        continue_buttons = [:next, :back, :cancel, :abort, :register, :extensions]

        ret = nil
        ret = Yast::UI.UserInput until continue_buttons.include?(ret)

        Wizard.RestoreNextButton

        ret
      end

      private

      def dialog_content
        VBox(
          Heading(_("The system is already registered.")),
          VSpacing(2),
          # button label
          PushButton(Id(:register), _("Register Again")),
          VSpacing(1),
          # button label
          PushButton(Id(:extensions), _("Select Extensions"))
        )
      end
    end
  end
end
