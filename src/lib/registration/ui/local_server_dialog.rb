
require "yast"
require "uri"

module Registration
  module UI
    class LocalServerDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts

      attr_accessor :local_url

      Yast.import "UI"
      Yast.import "Label"
      Yast.import "Report"

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

        dialog_content = local_server_dialog_content
        log.debug "URL dialog: #{dialog_content}"
        Yast::UI.OpenDialog(Opt(:decorated), dialog_content)

        begin
          handle_dialog
        ensure
          Yast::UI.CloseDialog
        end
      end

      private

      def handle_dialog
        ui = nil
        while ![:ok, :cancel].include?(ui)
          Yast::UI.SetFocus(:url)
          ui = Yast::UI.UserInput
          log.info "User input: #{ui}"

          if ui == :ok && !valid_url?
            # error message, the entered URL is not valid
            Yast::Report.Error(_("Invalid URL."))
            ui = nil
          end
        end

        (ui == :ok) ? Yast::UI.QueryWidget(Id(:url), :Value) : nil
      end

      def valid_url?
        uri = URI(Yast::UI.QueryWidget(Id(:url), :Value))
        (uri.is_a?(URI::HTTPS) || uri.is_a?(URI::HTTP)) && uri.host
      rescue URI::InvalidURIError
        false
      end

      def button_box
        [
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
        ]
      end

      # create dialog content
      def local_server_dialog_content
        MarginBox(1, 0.6,
          VBox(
            # input field label
            InputField(Id(:url), _("&Local Registration Server URL"), local_url),
            VSpacing(0.6),
            ButtonBox(*button_box)
          )
        )
      end
    end
  end
end
