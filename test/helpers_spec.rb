#! /usr/bin/env rspec

require_relative "spec_helper"

describe "Registration::Helpers" do
  describe ".service_description" do
    let(:slp_url) { "https://example.com/registration" }
    let(:slp_attributes) { double }
    let(:slp_service) { double }

    before do
      expect(slp_service).to receive(:attributes).and_return(slp_attributes)
      expect(slp_service).to receive(:slp_url).and_return("service:registration.suse:manager:#{slp_url}")
    end

    it "creates a label with description and url" do
      description = "Description"
      expect(slp_attributes).to receive(:to_h).and_return({description: description})
      expect(Registration::Helpers.service_description(slp_service)).to eq("#{description} (#{slp_url})")
    end

    it "creates a label with url only when description is missing" do
      expect(slp_attributes).to receive(:to_h).and_return({})
      expect(Registration::Helpers.service_description(slp_service)).to eq(slp_url)
    end
  end

  describe ".base_version" do
    it "returns the version if build suffix is missing" do
      expect(Registration::Helpers.base_version("12")).to eq("12")
      expect(Registration::Helpers.base_version("12.1")).to eq("12.1")
    end

    it "returns base version without build suffix" do
      expect(Registration::Helpers.base_version("12.1-1.47")).to eq("12.1")
      expect(Registration::Helpers.base_version("12.1-1")).to eq("12.1")
      expect(Registration::Helpers.base_version("12-1.47")).to eq("12")
      expect(Registration::Helpers.base_version("12-1")).to eq("12")
    end
  end

  describe ".insecure_registration" do
    context "outside installation/update" do
      before do
        allow(Yast::Mode).to receive(:installation).and_return(false)
        allow(Yast::Mode).to receive(:update).and_return(false)
      end

      it "returns false and does not check boot parameters" do
        expect(Yast::Linuxrc).to receive(:InstallInf).never
        expect(Registration::Helpers.insecure_registration).to eq(false)
      end
    end

    context "at installation" do
      before do
        allow(Yast::Mode).to receive(:installation).and_return(true)
        allow(Yast::Mode).to receive(:update).and_return(false)
      end

      it "returns false when reg_ssl_verify option is not used at boot commandline" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("reg_ssl_verify").
          and_return(nil)
        expect(Registration::Helpers.insecure_registration).to eq(false)
      end

      it "returns false when reg_ssl_verify=1 boot option is used" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("reg_ssl_verify").
          and_return("1")
        expect(Registration::Helpers.insecure_registration).to eq(false)
      end

      it "returns true when reg_ssl_verify=0 boot option is used" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("reg_ssl_verify").
          and_return("0")
        expect(Registration::Helpers.insecure_registration).to eq(true)
      end
    end
  end

  describe ".copy_certificate_to_target" do
    let(:cert_file) { SUSE::Connect::SSLCertificate::SERVER_CERT_FILE }

    it "does nothing when no SSL certificate has been imported" do
      expect(File).to receive(:exist?).with(cert_file).and_return(false)
      expect(FileUtils).to receive(:cp).never

      expect {Registration::Helpers.copy_certificate_to_target}.to_not raise_error
    end

    it "copies the certificate and updates all certificate links" do
      expect(File).to receive(:exist?).with(cert_file).and_return(true)
      expect(Yast::Installation).to receive(:destdir).and_return("/mnt")
      expect(FileUtils).to receive(:mkdir_p).with("/mnt" + File.dirname(cert_file))
      expect(FileUtils).to receive(:cp).with(cert_file, "/mnt" + cert_file)
      expect(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash"),
        SUSE::Connect::SSLCertificate::UPDATE_CERTIFICATES)

      expect {Registration::Helpers.copy_certificate_to_target}.to_not raise_error
    end
  end

  describe ".reset_registration_status" do
    let(:credentials) { ::Registration::Registration::SCC_CREDENTIALS }

    it "does nothing if there are no system credentials present" do
      expect(File).to receive(:exist?).with(credentials).and_return(false)
      expect(File).to receive(:unlink).never

      expect {Registration::Helpers.reset_registration_status}.to_not raise_error
    end

    it "removes system credentials if present" do
      expect(File).to receive(:exist?).with(credentials).and_return(true)
      expect(File).to receive(:unlink).with(credentials)

      expect {Registration::Helpers.reset_registration_status}.to_not raise_error
    end
  end

  describe ".render_erb_template" do
    it "renders specified ERB template file" do
      file = fixtures_file("template.erb")
      # this is used in the template
      @label = "FOO"
      expect(Registration::Helpers.render_erb_template(file, binding)).to eq("<h1>FOO</h1>\n")
    end
  end

  describe ".http_language" do
    it "returns the current Yast language" do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("en")
      expect(Registration::Helpers.http_language).to eq("en")
    end

    it "removes encoding suffix" do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("en.UTF-8")
      expect(Registration::Helpers.http_language).to eq("en")
    end

    it "replaces _ separator by -" do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("en_US.UTF-8")
      expect(Registration::Helpers.http_language).to eq("en-US")
    end

    it "returns nil for C locale" do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("C")
      expect(Registration::Helpers.http_language).to eq(nil)
    end

    it "returns nil for POSIX locale" do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("POSIX")
      expect(Registration::Helpers.http_language).to eq(nil)
    end
  end

  describe ".write_config" do
    it "writes the current configuration" do
      url = "https://example.com"
      expect(Registration::UrlHelpers).to receive(:registration_url) \
        .and_return(url)
      expect(Registration::Helpers).to receive(:insecure_registration) \
        .and_return(false)
      expect(SUSE::Connect::YaST).to receive(:write_config).with(
        url: url,
        insecure: false
      )

      Registration::Helpers.write_config
    end
  end

  describe ".run_network_configuration" do
    it "runs 'inst_lan' Yast client" do
      expect(Yast::WFM).to receive(:call).with("inst_lan", anything)

      Registration::Helpers.run_network_configuration
    end
  end

  describe ".collect_autoyast_config" do
    it "returns installation data as Autoyast hash" do
      options = Registration::Storage::InstallationOptions.instance
      options.email = "foo"
      options.reg_code = "bar"
      options.install_updates = true
      options.imported_cert_sha256_fingerprint = "AB:CD:EF"

      expect(Registration::UrlHelpers).to receive(:registration_url)

      addon = Registration::Addon.new(addon_generator(
          "zypper_name" => "sle-sdk",
          "version" => "12",
          "arch" => "x86_64",
          "release_type" => nil
        )
      )
      expect(Registration::Addon).to receive(:registered).and_return([addon])

      expect(Registration::Helpers.collect_autoyast_config({})).to eq(
        "do_registration" => true,
        "email" => "foo",
        "reg_code" => "bar",
        "install_updates" => true,
        "addons" => [{"name" => "sle-sdk", "arch" => "x86_64", "version" => "12",
            "release_type" => "nil", "reg_code" => ""}],
        "reg_server_cert_fingerprint" => "AB:CD:EF",
        "reg_server_cert_fingerprint_type" => "SHA256"
      )
    end
  end

  describe ".hide_reg_codes" do
    it "returns the original value if the input is not a Hash" do
      test = "test"
      expect(Registration::Helpers.hide_reg_codes(test)).to be(test)
    end

    it "it does not change anything if there is no registration code in the Hash" do
      test = { "test" => "foo" }
      expect(Registration::Helpers.hide_reg_codes(test)).to eq(test)
    end

    it "it replaces \"reg_code\" value by [FILTERED]" do
      test = { "reg_code" => "foo" }
      expect(Registration::Helpers.hide_reg_codes(test)).to eq("reg_code" => "[FILTERED]")
    end

    it "it replaces \"reg_code\" also in nested \"addons\" list" do
      test = { "addons" => [{ "reg_code" => "foo" }, { "reg_code" => "bar" }] }
      expect(Registration::Helpers.hide_reg_codes(test)).to eq(
        "addons" => [{ "reg_code" => "[FILTERED]" }, { "reg_code" => "[FILTERED]" }])
    end

    it "it does not modify the original input value" do
      test = { "addons" => [{ "reg_code" => "foo" }, { "reg_code" => "bar" }] }
      Registration::Helpers.hide_reg_codes(test)
      # make sure the copy is deep, i.e. the original value is unchanged
      expect(test).to eq({ "addons" => [{ "reg_code" => "foo" }, { "reg_code" => "bar" }] })
    end
  end

end
