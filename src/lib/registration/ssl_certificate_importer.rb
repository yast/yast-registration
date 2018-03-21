
require "openssl"
require "suse/connect"
# require "registration/downloader"
# require "registration/fingerprint"
require "yast2/execute"

module Registration
  # class for importing the SSL certificate into the system or into the inst-sys
  class SslCertificateImporter
    Yast.import "Stage"

    attr_reader :cert

    # Path to store the certificate of the registration server
    #
    # During installation, the certificate should be written to a read-write
    # directory. On an installed system, the method relies on SUSEConnect.
    #
    # @return [String] Path to store the certificate
    def self.default_certificate_path
      Yast::Stage.initial ? INSTSYS_SERVER_CERT_FILE : SUSE::Connect::YaST::SERVER_CERT_FILE
    end

    def initialize(cert)
      @cert = cert
    end

    def self.load_from_system(root)
      # SLE12 certificate path
      cert_file = File.join(Yast::Installation.destdir, SUSE::Connect::YaST::SERVER_CERT_FILE)

      if !File.exist?(cert_file)
        # try the the SLE11 certificate path as well
        # see https://github.com/yast/yast-registration/blob/Code-11-SP3/src/modules/Register.ycp#L296-L297
        cert_file = File.join(Yast::Installation.destdir,
          "/etc/ssl/certs/registration-server.pem")
      end

      if File.exist?(cert_file)
        log.info("Reading the SSL certificate from the old system (#{cert_file})...")
        
        cert = SslCertificate.load_file(cert_file)
      end
      
      # create the importer with the loaded certificate
      SslCertificateImporter.new(cert)
    end

    def empty?
      !cert.nil?
    end

    # Path to temporal CA certificates (to be used only in instsys)
    TMP_CA_CERTS_DIR = "/var/lib/YaST2/ca-certificates".freeze

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
      Yast::Stage.initial ? import_to_instsys : import_to_system
    end

  private

    # Import a certificate to the installed system
    #
    # @return [Boolean] true if import was successful; false otherwise.
    def import_to_system
      ::SUSE::Connect::YaST.import_certificate(cert.x509_cert)
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
      File.write(self.class.default_certificate_path, cert.x509_cert.to_pem)

      # Update database
      update_instsys_ca
    end

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
      return false if files.empty?
      targets = ["pem", "openssl"].map { |d| File.join(CA_CERTS_DIR, d) }
      new_files = targets.each_with_object([]) do |subdir, memo|
        FileUtils.mkdir_p(subdir) unless Dir.exist?(subdir)
        files.each do |file|
          # FileUtils.cp does not seem to allow copying the links without dereferencing them.
          Yast::Execute.locally("cp", "--no-dereference", "--preserve=links", file, subdir)
          memo << File.join(subdir, File.basename(file))
        end
      end

      # Cleanup
      FileUtils.rm_rf(TMP_CA_CERTS_DIR)

      # Check that last file was copied to return true or false
      File.exist?(new_files.last)
    end
  end
end
