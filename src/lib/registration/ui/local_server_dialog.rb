
require "yast"

module Registration
  module UI

    class LocalServerDialog
      include Yast::Logger
      include Yast::I18n
      extend Yast::I18n
      include Yast::UIShortcuts

      attr_accessor :local_url

      Yast.import "UI"
      Yast.import "Label"

      # create a new dialog for editing server URL and run it
      # @param url [String] current server URL
      # @return [String,nil] entered URL or nil when canceled
      def self.run(url)
        dialog = LocalServerDialog.new(url)
        dialog.run
      end

      # @param url [String] current server URL
      def initialize(url)
        textdomain "registration"
        @local_url = url || ""
      end

      # display the dialog and wait for a button click
      # @return [String,nil] entered URL or nil when canceled
      def run
        log.info "Displaying local server URL: #{local_url}"

        dialog_content = local_sever_dialog_content
        log.debug "URL dialog: #{dialog_content}"
        Yast::UI.OpenDialog(Opt(:decorated), dialog_content)

        begin
          Yast::UI.SetFocus(:url)
          ui = Yast::UI.UserInput
          log.info "User input: #{ui}"

          (ui == :ok) ? Yast::UI.QueryWidget(Id(:url), :Value) : nil
        ensure
          Yast::UI.CloseDialog
        end
      end

      private

      # create dialog content
      def local_sever_dialog_content
        MarginBox(1, 0.6,
          VBox(
            # input field label
            InputField(Id(:url), _("&Local Registration Server URL"), local_url),
            VSpacing(0.6),
            ButtonBox(
              PushButton(
                Id(:ok),
                Opt(:key_F10, :okButton, :default),
                Yast::Label.OKButton
              ),
              PushButton(
                Id(:cancel),
                Opt(:key_F9, :cancelButton),
                Yast::Label.CancelButton
              )
            )
          )
        )
      end

    end
  end
end

