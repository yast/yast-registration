#! /usr/bin/env rspec

require_relative "spec_helper"
require_relative "yast_stubs"

describe "Registration::Helpers" do
  before do
    stub_yast_require
    require "registration/helpers"
  end

  describe ".registration_url" do
    let(:yast_mode) { double("Yast::Mode") }
    let(:yast_linuxrc) { double("Yast::Linuxrc") }
    let(:yast_wfm) { double("Yast::WFM") }

    before do
      stub_const("Yast::Mode", yast_mode)
      stub_const("Yast::Linuxrc", yast_linuxrc)
      stub_const("Yast::WFM", yast_wfm)
      # reset the cache befor each test
      ::Registration::Storage::Cache.instance.reg_url_cached = nil
    end

    context "at installation" do
      before do
        allow(yast_mode).to receive(:mode).and_return("installation")
      end

      context "no local registration server is announced via SLP" do
        it "returns 'regurl' boot parameter from Linuxrc" do
          url = "https://example.com/register"
          expect(yast_linuxrc).to receive(:InstallInf).with("regurl").and_return(url)
          # make sure no SLP discovery is executed, the boot parameter has higher priority
          expect(yast_wfm).to receive(:call).with("discover_registration_services").never
          expect(Registration::Helpers.registration_url).to eq(url)
        end

        it "returns nil when no custom URL is required in Linuxrc" do
          expect(yast_linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)
          expect(yast_wfm).to receive(:call).with("discover_registration_services").and_return(nil)
          expect(Registration::Helpers.registration_url).to be_nil
        end
      end

      context "no boot parameter is used and a SLP server is announced" do
        before do
          # no boot parameter passed, it would have higher priority
          expect(yast_linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)
        end

        it "returns the SLP server selected by user" do
          slp_url = "https://example.com/register"
          expect(yast_wfm).to receive(:call).with("discover_registration_services").and_return(slp_url)
          expect(Registration::Helpers.registration_url).to eq(slp_url)
        end

        it "returns nil when the SLP dialog is canceled" do
          expect(yast_wfm).to receive(:call).with("discover_registration_services").and_return(nil)
          expect(Registration::Helpers.registration_url).to be_nil
        end

      end
    end

    context "at installed system" do
      before do
        allow(yast_mode).to receive(:mode).and_return("normal")
        allow(yast_wfm).to receive(:call).with("discover_registration_services").and_return(nil)
      end

      it "ignores Linuxrc boot parameters" do
        # must not ask Linuxrc at all
        expect(yast_linuxrc).to receive(:InstallInf).never
        # stub config file reading
        expect_any_instance_of(SUSE::Connect::Config).to receive(:url)
        expect(Registration::Helpers.registration_url).to be_nil
      end

      it "reads the URL from config file if present" do
        # must not ask Linuxrc at all
        expect(yast_linuxrc).to receive(:InstallInf).never
        # stub config file reading
        url = "https://example.com"
        expect_any_instance_of(SUSE::Connect::Config).to receive(:url).twice.and_return(url)
        expect(Registration::Helpers.registration_url).to eq(url)
      end
    end

    context "at upgrade" do
      let(:yast_installation) { double("Yast::Instrallation") }
      let(:suse_register) { "/mnt/etc/suseRegister.conf" }

      before do
        allow(yast_mode).to receive(:mode).and_return("update")
        allow(yast_wfm).to receive(:call).with("discover_registration_services").and_return(nil)

        stub_const("Yast::Installation", yast_installation)
        allow(yast_installation).to receive(:destdir).and_return("/mnt")
      end

      it "returns 'regurl' boot parameter from Linuxrc" do
        url = "https://example.com/register"
        expect(yast_linuxrc).to receive(:InstallInf).with("regurl").and_return(url)
        # make sure no SLP discovery is executed, the boot parameter has higher priority
        expect(yast_wfm).to receive(:call).with("discover_registration_services").never
        expect(Registration::Helpers.registration_url).to eq(url)
      end

      context "the system has been already registered" do
        before do
          expect(File).to receive(:exist?).with("/mnt/etc/zypp/credentials.d/NCCcredentials").and_return(true)
          expect(yast_linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)
        end

        it "return default when NCC registration server was used" do
          expect(File).to receive(:exist?).with(suse_register).and_return(true)
          expect(File).to receive(:readlines).with(suse_register).\
            and_return(File.readlines(fixtures_file("old_conf_ncc/etc/suseRegister.conf")))

          expect(Registration::Helpers.registration_url).to be_nil
        end

        it "return URL of SMT server when used" do
          expect(File).to receive(:exist?).with(suse_register).and_return(true)
          expect(File).to receive(:readlines).with(suse_register).\
            and_return(File.readlines(fixtures_file("old_conf_custom/etc/suseRegister.conf")))

          expect(Registration::Helpers.registration_url).to eq("https://myserver.com")
        end
      end

      context "the system has not been registered" do
        before do
          expect(File).to receive(:exist?).with("/mnt/etc/zypp/credentials.d/NCCcredentials").and_return(false)
          expect(yast_linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)
        end

        it "calls SLP discovery" do
          slp_url = "https://slp.example.com/register"
          expect(yast_wfm).to receive(:call).with("discover_registration_services").and_return(slp_url)
          expect(Registration::Helpers.registration_url).to eq(slp_url)
        end
      end
    end

    context "at unknown mode" do
      before do
        allow(yast_mode).to receive(:mode).and_return("config")
      end

      it "returns nil (default URL)" do
        expect(Registration::Helpers.registration_url).to be_nil
      end
    end
  end

  describe ".service_url" do
    it "converts a SLP service to plain URL" do
      url = "https://example.com/registration"
      service1 = "service:registration.suse:manager:#{url}"
      service2 = "service:registration.suse:smt:#{url}"
      expect(Registration::Helpers.service_url(service1)).to eq(url)
      expect(Registration::Helpers.service_url(service2)).to eq(url)
    end
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

  describe ".credentials_from_url" do
    it "returns credentials parameter from URL" do
      url = "https://scc.suse.com/service/repo/repoindex.xml?credentials=SLES_credentials"
      expect(Registration::Helpers.credentials_from_url(url)).to eq("SLES_credentials")
    end

    it "returns nil if the URL misses credentials parameter" do
      url = "https://scc.suse.com/service/repo/repoindex.xml?nocredentials=SLES_credentials"
      expect(Registration::Helpers.credentials_from_url(url)).to eq(nil)
    end

    it "raises URI::InvalidURIError when URL is invalid" do
      url = ":foo:"
      expect{Registration::Helpers.credentials_from_url(url)}.to raise_error(URI::InvalidURIError)
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

end
