
require "openssl"
require "suse/connect"
require "registration/downloader"
require "registration/fingerprint"
require "yast2/execute"

module Registration
  # class handling SSL certificate
  # TODO: move it to yast2 to share it?
  class SslCertificate
    Yast.import "Mode"

    # Path to the registration certificate in the instsys
    INSTSYS_SERVER_CERT_FILE = "/etc/pki/trust/anchors/registration_server.pem".freeze
    # Path to system CA certificates
    CA_CERTS_DIR = "/var/lib/ca-certificates".freeze

    attr_reader :x509_cert

    # Path to store the certificate of the registration server
    #
    # During installation, the certificate should be written to a read-write
    # directory. On an installed system, the method relies in SUSEConnect.
    #
    # @return [String] Path to store the certificate
    def self.default_certificate_path
      if Yast::Mode.installation || Yast::Mode.update
        INSTSYS_SERVER_CERT_FILE
      else
        SUSE::Connect::YaST::SERVER_CERT_FILE
      end
    end

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

    # Path to temporal CA certificates (to be used only in instsys)
    TMP_CA_CERTS_DIR = "/var/lib/YaST2/ca-certificates".freeze

    # Update instys CA certificates
    #
    # update-ca-certificates script cannot be used in inst-sys.
    # See bsc#981428 and bsc#989787.
    #
    # @return [Boolean] true if update was successful; false otherwise.
    #
    # @see CA_CERTS_DIR
    # @see TMP_CA_CERTS_DIR
    def self.update_instsys_ca
      # Update database
      Yast::Execute.locally("trust", "extract", "--format=openssl-directory", "--filter=ca-anchors",
        "--overwrite", TMP_CA_CERTS_DIR)

      # Copy certificates/links
      files = Dir[File.join(TMP_CA_CERTS_DIR, "*")]
      targets = ["pem", "openssl"].map { |d| File.join(CA_CERTS_DIR, d) }
      targets.each do |subdir|
        FileUtils.mkdir_p(subdir) unless Dir.exist?(subdir)
        files.each do |file|
          # FileUtils.cp does not seem to allow copying the links without dereferencing them.
          Yast::Execute.locally("cp", "--no-dereference", "--preserve=links", file, subdir)
        end
      end

      # Cleanup
      FileUtils.rm_rf(TMP_CA_CERTS_DIR)
      true
    rescue Cheetah::ExecutionFailed => e
      log.error("Error updating instsys CA certificates: #{e.message}")
      false
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

    # Import the certificate
    #
    # Depending if running in installation or in a installed system,
    # it will rely on #import_to_instsys or #import_to_system methods.
    #
    # @return [true] true if import was successful
    #
    # @raise Connect::SystemCallError
    # @raise Cheetah::ExecutionFailed

    # @see #import_to_system
    # @see #import_to_instsys
    def import
      (Yast::Mode.installation || Yast::Mode.update) ? import_to_instsys : import_to_system
    end

    # Import a certificate to the installed system
    #
    # @return [Boolean] true if import was successful; false otherwise.
    def import_to_system
      ::SUSE::Connect::YaST.import_certificate(x509_cert)
      true
    rescue ::SUSE::Connect::SystemCallError => e
      log.error("Error updating system CA certificates: #{e.message}")
      false
    end

    # Import the certificate to the installation system
    #
    # This method exists because the procedure to import certificates
    # to installation system is slightly different to the one followed
    # to import certificates to a installed system.
    #
    # @return [Boolean] true if import was successful; false otherwise.
    #
    # @see update_instsys_ca
    def import_to_instsys
      # Copy certificate
      File.write(self.class.default_certificate_path, x509_cert.to_pem)

      # Update database
      self.class.update_instsys_ca
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
