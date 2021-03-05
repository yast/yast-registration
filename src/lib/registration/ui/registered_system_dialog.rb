
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

      # Displays and run the status dialog for an already registered system
      #
      # @param extensions [Boolean] Whether "Select extensions" button shoudl be enabled
      # @param registration [Boolean] Whether the "Register Again" button should be enabled
      #
      # @return [Symbol] user input
      def self.run(extensions: true, registration: true)
        RegisteredSystemDialog.new(extensions: extensions, registration: registration).run
      end

      # Constructor
      #
      # @param extensions [Boolean] Whether "Select extensions" button shoudl be enabled
      # @param registration [Boolean] Whether the "Register Again" button should be enabled
      def initialize(extensions: true, registration: true)
        textdomain "registration"

        @extensions = extensions
        @registration = registration
      end

      # Display and run the dialog
      #
      # @return [Symbol] user input
      def run
        Wizard.SetContents(
          # dialog title
          _("Registration"),
          dialog_content,
          help_text,
          true,
          true
        )

        Yast::UI.ChangeWidget(Id(:extensions), :Enabled, extensions)
        Yast::UI.ChangeWidget(Id(:register), :Enabled, registration)
        Wizard.SetNextButton(:next, Label.FinishButton) if Mode.normal

        ret = Yast::UI.UserInput until available_actions.include?(ret)

        Wizard.RestoreNextButton

        ret
      end

    private

      attr_reader :extensions, :registration

      # Available dialog actions
      #
      # @return [Symbol]
      def available_actions
        [:next, :back, :cancel, :abort, :register, :extensions]
      end

      # The dialog content
      #
      # @return [Yast::Term] UI term
      def dialog_content
        VBox(
          Heading(_("The system is already registered.")),
          VSpacing(2),
          PushButton(Id(:extensions), _("Select Extensions")),
          VSpacing(1),
          PushButton(Id(:register), _("Register Again"))
        )
      end

      # The dialog's help text
      #
      # @return [String]
      def help_text
        text = [_("<p>The system is already registered.</p>")]
        text << actions_help
        text << _("<p>If you want to deregister your system you need to log "\
                  "into the SUSE Customer Center and remove the system manually there.</p>")
        text.join
      end

      # The help text for enabled actions
      #
      # @return [String]
      def actions_help
        if extensions && registration
          _("<p>You can re-register it again or register additional "\
            "extension or modules to enhance the functionality of the system.</p>")
        elsif extensions
          _("<p>You can register additional extension or modules "\
            "to enhance the functionality of the system.</p>")
        elsif registration
          _("<p>You can re-register it again.")
        else
          _("<p>At this moment, you can neither re-register it again " \
            "nor register additional extensions</p>")
        end
      end
    end
  end
end
