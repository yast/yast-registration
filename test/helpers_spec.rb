#! /usr/bin/env rspec

require_relative "spec_helper"
require_relative "yast_stubs"

describe "Registration::Helpers" do
  let(:yast_wfm) { double("Yast::WFM") }

  before do
    stub_yast_require
    require "registration/helpers"
    stub_const("Yast::WFM", yast_wfm)
  end

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
      expect(slp_attributes).to receive(:to_h).and_return({:description => description})
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
    let(:yast_mode) { double("Yast::Mode") }
    let(:yast_linuxrc) { double("Yast::Linuxrc") }

    before do
      stub_const("Yast::Mode", yast_mode)
      stub_const("Yast::Linuxrc", yast_linuxrc)
    end

    context "outside installation/update" do
      before do
        allow(yast_mode).to receive(:installation).and_return(false)
        allow(yast_mode).to receive(:update).and_return(false)
      end

      it "returns false and does not check boot parameters" do
        expect(yast_linuxrc).to receive(:InstallInf).never
        expect(Registration::Helpers.insecure_registration).to eq(false)
      end
    end

    context "at installation" do
      before do
        allow(yast_mode).to receive(:installation).and_return(true)
        allow(yast_mode).to receive(:update).and_return(false)
      end

      it "returns false when reg_ssl_verify option is not used at boot commandline" do
        expect(yast_linuxrc).to receive(:InstallInf).with("reg_ssl_verify").
          and_return(nil)
        expect(Registration::Helpers.insecure_registration).to eq(false)
      end

      it "returns false when reg_ssl_verify=1 boot option is used" do
        expect(yast_linuxrc).to receive(:InstallInf).with("reg_ssl_verify").
          and_return("1")
        expect(Registration::Helpers.insecure_registration).to eq(false)
      end

      it "returns true when reg_ssl_verify=0 boot option is used" do
        expect(yast_linuxrc).to receive(:InstallInf).with("reg_ssl_verify").
          and_return("0")
        expect(Registration::Helpers.insecure_registration).to eq(true)
      end
    end
  end

  describe ".copy_certificate_to_target" do
    let(:yast_scr) { double("Yast::SCR") }
    let(:yast_installation) { double("Yast::Installation") }
    let(:cert_file) { SUSE::Connect::SSLCertificate::SERVER_CERT_FILE }

    before do
      stub_const("Yast::SCR", yast_scr)
      stub_const("Yast::Installation", yast_installation)
    end

    it "does nothing when no SSL certificate has been imported" do
      expect(File).to receive(:exist?).with(cert_file).and_return(false)
      expect(FileUtils).to receive(:cp).never

      expect {Registration::Helpers.copy_certificate_to_target}.to_not raise_error
    end

    it "copies the certificate and updates all certificate links" do
      expect(File).to receive(:exist?).with(cert_file).and_return(true)
      expect(yast_installation).to receive(:destdir).and_return("/mnt")
      expect(FileUtils).to receive(:mkdir_p).with("/mnt" + File.dirname(cert_file))
      expect(FileUtils).to receive(:cp).with(cert_file, "/mnt" + cert_file)
      expect(yast_scr).to receive(:Execute).with(Yast::Path.new(".target.bash"),
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

  describe ".language" do
    it "returns the current Yast language" do
      expect(yast_wfm).to receive(:GetLanguage).and_return("en")
      expect(Registration::Helpers.language).to eq("en")
    end

    it "removes encoding suffix" do
      expect(yast_wfm).to receive(:GetLanguage).and_return("en.UTF-8")
      expect(Registration::Helpers.language).to eq("en")
    end

    it "replaces _ separator by -" do
      expect(yast_wfm).to receive(:GetLanguage).and_return("en_US.UTF-8")
      expect(Registration::Helpers.language).to eq("en-US")
    end

    it "returns nil for C locale" do
      expect(yast_wfm).to receive(:GetLanguage).and_return("C")
      expect(Registration::Helpers.language).to eq(nil)
    end

    it "returns nil for POSIX locale" do
      expect(yast_wfm).to receive(:GetLanguage).and_return("POSIX")
      expect(Registration::Helpers.language).to eq(nil)
    end
  end

  describe ".write_config" do
    it "wtites the current configuration" do
      url = "https://example.com"
      expect(Registration::UrlHelpers).to receive(:registration_url) \
        .and_return(url)
      expect(Registration::Helpers).to receive(:insecure_registration) \
        .and_return(false)
      expect(SUSE::Connect::YaST).to receive(:write_config).with(
        :url => url,
        :insecure => false
      )

      Registration::Helpers.write_config
    end
  end

  describe ".run_network_configuration" do
    it "runs 'inst_lan' Yast client" do
      expect(yast_wfm).to receive(:call).with("inst_lan", anything)

      Registration::Helpers.run_network_configuration
    end
  end

end
