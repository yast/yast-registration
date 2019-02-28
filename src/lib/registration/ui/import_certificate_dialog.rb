
require "erb"
require "yast"

require "registration/fingerprint"
require "registration/ssl_certificate_details"
require "registration/ssl_error_codes"
require "registration/url_helpers"

module Registration
  module UI
    # this class displays and runs the dialog for importing a SSL certificate
    class ImportCertificateDialog
      include ERB::Util
      include Yast::Logger
      include Yast::I18n
      extend Yast::I18n
      include Yast::UIShortcuts

      attr_accessor :certificate, :error_code

      Yast.import "UI"
      Yast.import "Label"

      # create a new dialog for importing a SSL certificate and run it
      # @param cert [Registration::SslCertitificate] certificate to display
      # @return [Symbol] user input (:import, :cancel)
      def self.run(cert, error_code)
        dialog = ImportCertificateDialog.new(cert, error_code)
        dialog.run
      end

      # the constructor
      # @param cert [Registration::SslCertitificate] certificate to display
      # @param error_code [Integer] OpenSSL error code
      def initialize(cert, error_code)
        textdomain "registration"
        @certificate = cert
        @error_code = error_code
      end

      # display the dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        log.info "Certificate import dialog: issuer: #{certificate.issuer_name}, " \
          "subject: #{certificate.subject_name}, SHA1: " \
          "#{certificate.fingerprint(Fingerprint::SHA1).value}"

        Yast::UI.OpenDialog(Opt(:decorated), import_dialog_content)

        begin
          handle_dialog
        ensure
          Yast::UI.CloseDialog
        end
      end

    private

      # UI widgets with the certificate description
      # @return [Yast::Term] UI term
      def certificate_box
        VBox(
          HSpacing(75),
          MarginBox(0.4, 0.4, RichText(certificate_description)),
          ButtonBox(
            # push button
            PushButton(Id(:import), Opt(:key_F10, :okButton), _("&Trust and Import")),
            PushButton(
              Id(:cancel),
              Opt(:key_F9, :cancelButton),
              Yast::Label.CancelButton
            )
          )
        )
      end

      # the main dialog content
      # @return [Yast::Term] UI term
      def import_dialog_content
        displayinfo = Yast::UI.GetDisplayInfo
        # hide additional help text in narrow terminals
        hide_help = displayinfo["TextMode"] && displayinfo["Width"] < 105

        window_height = displayinfo["Height"]
        window_height = 26 if window_height > 26

        HBox(
          VSpacing(window_height),
          # left-side help
          hide_help ? Empty() : HWeight(2, VBox(RichText(Opt(:disabled), warning_text))),
          HSpacing(1),
          HWeight(5, certificate_box)
        )
      end

      # the main UI event loop
      # @return [Symbol] the user input
      def handle_dialog
        Yast::UI.SetFocus(:cancel)
        ui = Yast::UI.UserInput
        log.info "User input: #{ui}"
        ui
      end

      # render Richtext description with the certificate details
      def certificate_description
        msg = _(SslErrorCodes::OPENSSL_ERROR_MESSAGES[error_code])
        url = UrlHelpers.registration_url || SUSE::Connect::YaST::DEFAULT_URL
        details = SslCertificateDetails.new(certificate)

        "<h2>#{_("Secure Connection Error")}</h2>\n" \
          "<p>#{_("Details:")} #{h(url)}: #{h(msg)}</p>\n" \
          "<h3>#{_("Failed Certificate Details")}</h3>\n" +
          details.richtext_summary
      end

      # inline help text displayed in the import dialog
      # @return [String] translated help text
      def warning_text
        # help text (RichText) for importing a SSL certificate (1/5)
        _("<p>Secure connections (e.g. HTTPS) use SSL certificates for " \
        "verifying the authenticity of the server and encrypting the data " \
        "being transferred.</p>") +

          # help text (RichText) for importing a SSL certificate (2/5)
          _("<p>You can choose to import the certificate into the list of known " \
              "certificate authorities (CA), meaning that you trust the subject " \
              "and the issuer of the unknown certificate.</p>") +

          # help text (RichText) for importing a SSL certificate (3/5)
          _("<p>Importing a certificate will, for example, allow you to use " \
          "a self-signed certificate.</p>") +

          # help text (RichText) for importing a SSL certificate (4/5)
          _("<p><b>Important:</b> You should always verify the fingerprints " \
          "of certificates you import to ensure they are genuine.</p>") +

          # help text (RichText) for importing a SSL certificate (5/5)
          _("<p><b>Importing an unknown certificate without " \
              "verification is a big security risk.</b></p>")
      end
    end
  end
end
