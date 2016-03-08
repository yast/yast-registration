
require "yast"
require "erb"

require "registration/ssl_certificate"
require "registration/helpers"

module Registration
  # class handling SSL certificate
  # TODO: move it to yast2 to share it?
  class SslCertificateDetails
    include Yast::I18n
    include ERB::Util

    # indent size used in summary text
    INDENT = " " * 3

    def initialize(certificate)
      textdomain "registration"
      @certificate = certificate
    end

    def subject
      identity_details(certificate.subject_name, certificate.subject_organization,
        certificate.subject_organization_unit)
    end

    def issuer
      identity_details(certificate.issuer_name, certificate.issuer_organization,
        certificate.issuer_organization_unit)
    end

    def summary(small_space: false)
      summary = _("Certificate:") + "\n" + _("Issued To") + "\n" + subject +
        "\n" + _("Issued By")  + "\n" + issuer + "\n" + _("SHA1 Fingerprint: ") +
        "\n" + INDENT + certificate.fingerprint(Fingerprint::SHA1).value + "\n" +
        _("SHA256 Fingerprint: ")  + "\n"

      sha256 = certificate.fingerprint(Fingerprint::SHA256).value
      if small_space
        # split the long SHA256 digest to two lines in small text mode UI
        summary += INDENT + sha256[0..59] + "\n" + INDENT + sha256[60..-1]
      else
        summary += INDENT + sha256
      end

      summary
    end

    def richtext_summary
      Helpers.render_erb_template("certificate_summary.erb", binding)
    end

  private

    attr_reader :certificate

    def identity_details(cn, o, ou)
      # label followed by the SSL certificate identification
      _("Common Name (CN): ") + (cn || "") + "\n" +
        # label followed by the SSL certificate identification
        _("Organization (O): ") + (o || "") + "\n" +
        # label followed by the SSL certificate identification
        _("Organization Unit (OU): ") + (ou || "") + "\n"
    end
  end
end
