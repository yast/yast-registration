
require "erb"
require "yast"

require "yast/suse_connect"
require "registration/helpers"
require "registration/storage"

module Registration
  module UI

    class ImportCertificateDialog
      include Yast::Logger
      include Yast::I18n
      extend Yast::I18n
      include Yast::UIShortcuts
      include ERB::Util

      attr_accessor :certificate

      # error code => translatable error message
      # @see https://www.openssl.org/docs/apps/verify.html
      # @note the text messages need to be translated at runtime via _() call
      OPENSSL_ERROR_MESSAGES = {
        # SSL error message
        10 => N_("Certificate has expired"),
        # SSL error message
        18 => N_("Self signed certificate"),
        # SSL error message
        19 => N_("Self signed certificate in certificate chain")
      }

      Yast.import "UI"
      Yast.import "Label"

      # create a new dialog for importing a SSL certificate and run it
      # @param cert [OpenSSL::X509::Certificate] certificate to display
      # @return [Symbol] user input (:import, :cancel)
      def self.run(cert)
        dialog = ImportCertificateDialog.new(cert)
        dialog.run
      end

      # @param cert [OpenSSL::X509::Certificate] certificate to display
      def initialize(cert)
        textdomain "registration"
        @certificate = cert
      end

      # display the dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        log.info "Displaying certificate import dialog:"
        log.info " * Issuer: #{@certificate.issuer}"
        log.info " * Subject: #{@certificate.subject}"
        log.info " * SHA1: #{::SUSE::Connect::SSLCertificate.sha1_fingerprint(@certificate)}"

        dialog_content = import_dialog_content
        log.debug "Certificate import dialog: #{dialog_content}"
        Yast::UI.OpenDialog(Opt(:decorated), dialog_content)

        begin
          Yast::UI.SetFocus(:cancel)
          ui = Yast::UI.UserInput
          log.info "User input: #{ui}"
          return ui
        ensure
          Yast::UI.CloseDialog
        end
      end

      private

      # create dialog content
      def import_dialog_content
        displayinfo = Yast::UI.GetDisplayInfo
        # hide additional help text in narrow terminals
        hide_help = displayinfo["TextMode"] && displayinfo["Width"] < 105

        window_height = displayinfo["Height"]
        window_height = 25 if window_height > 25

        HBox(
          VSpacing(window_height),
          # left-side help
          hide_help ?
            Empty() :
            HWeight(2, VBox(RichText(Opt(:disabled), warning_text))),
          HSpacing(1),
          HWeight(
            5,
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
          )
        )
      end

      # render Richtext description with the certificate details
      def certificate_description
        # use erb template for rendering the richtext summary
        erb_file = File.expand_path("../../../../data/registration/certificate_summary.erb", __FILE__)

        log.info "Loading ERB template #{erb_file}"
        erb = ERB.new(File.read(erb_file))

        @issuer = @certificate.issuer
        @subject = @certificate.subject
        # render the ERB template in the context of the current object
        erb.result(binding)
      end

      # inline help text displayed in the import dialog
      def warning_text
        # help text (RichText) for importing a SSL certificate (1/5)
        _("<p>Secure connection (HTTPS) uses SSL certificates for verifying the " \
            "authenticity of the server and for encrypting the transferred data.</p>") +

          # help text (RichText) for importing a SSL certificate (2/5)
        _("<p>You can choose to import the certificate it into the list of known " \
            "certificate autohorities (CA), meaning that you trust the subject " \
            "and the issuer of the unknown certificate.</p>") +

          # help text (RichText) for importing a SSL certificate (3/5)
        _("<p>Importing a certificate will allow to use for example a " \
            "self-signed certificate.</p>") +

          # help text (RichText) for importing a SSL certificate (4/5)
        _("<p><b>Important:</b> You should verify the fingerprint of the " \
            "certificate to be sure you import the genuine certificate from " \
            "the requested server.</p>") +

          # help text (RichText) for importing a SSL certificate (5/5)
        _("<p><b>Importing an unknown certificate without " \
            "verification is a big security risk.</b></p>")
      end

    end
  end
end

