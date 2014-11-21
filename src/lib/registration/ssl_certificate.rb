
require "openssl"
require "suse/connect"
require "registration/downloader"
require "registration/fingerprint"

module Registration
  # class handling SSL certificate
  # TODO: move it to yast2 to share it?
  class SslCertificate
    attr_reader :x509_cert

    def initialize(x509_cert)
      @x509_cert = x509_cert
    end

    def self.load_file(file)
      load(File.read(file))
    end

    def self.load(data)
      cert = OpenSSL::X509::Certificate.new(data)
      SslCertificate.new(cert)
    end

    def self.download(url, insecure: false)
      result = Downloader.download(url, insecure: insecure)
      load(result)
    end

    # certificate serial number (in HEX format, e.g. AB:CD:42:FF...)
    def serial
      x509_cert.serial.to_s(16).scan(/../).join(":")
    end

    def issued_on
      x509_cert.not_before.localtime.strftime("%F")
    end

    def valid_yet?
      Time.now > x509_cert.not_before
    end

    def expires_on
      x509_cert.not_after.localtime.strftime("%F")
    end

    def expired?
      Time.now > x509_cert.not_after
    end

    def subject_name
      find_subject_attribute("CN")
    end

    def subject_organization
      find_subject_attribute("O")
    end

    def subject_organization_unit
      find_subject_attribute("OU")
    end

    def issuer_name
      find_issuer_attribute("CN")
    end

    def issuer_organization
      find_issuer_attribute("O")
    end

    def issuer_organization_unit
      find_issuer_attribute("OU")
    end

    def fingerprint(sum)
      case sum.upcase
      when Fingerprint::SHA1
        sha1_fingerprint
      when Fingerprint::SHA256
        sha256_fingerprint
      else
        raise "Unsupported checksum type '#{sum}'"
      end
    end

    def import_to_system
      ::SUSE::Connect::YaST.import_certificate(x509_cert)
    end

    private

    # @param x509_name [OpenSSL::X509::Name] name object
    # @param attribute [String] requested attribute name. e.g. "CN"
    # @return attribut value or nil if not defined
    def find_name_attribute(x509_name, attribute)
      # to_a returns an attribute list, e.g.:
      # [["CN", "linux", 19], ["emailAddress", "root@...", 22], ["O", "YaST", 19], ...]
      _attr, value, _code = x509_name.to_a.find { |a| a.first == attribute }
      value
    end

    def find_issuer_attribute(attribute)
      find_name_attribute(x509_cert.issuer, attribute)
    end

    def find_subject_attribute(attribute)
      find_name_attribute(x509_cert.subject, attribute)
    end

    def sha1_fingerprint
      Fingerprint.new(
        Fingerprint::SHA1,
        ::SUSE::Connect::YaST.cert_sha1_fingerprint(x509_cert)
      )
    end

    def sha256_fingerprint
      Fingerprint.new(
        Fingerprint::SHA256,
        ::SUSE::Connect::YaST.cert_sha256_fingerprint(x509_cert)
      )
    end
  end
end
