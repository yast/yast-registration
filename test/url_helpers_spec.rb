#! /usr/bin/env rspec

require_relative "spec_helper"

describe "Registration::UrlHelpers" do
  describe ".registration_url" do

    before do
      # reset the cache before each test
      ::Registration::Storage::Cache.instance.reg_url_cached = nil
    end

    context "at installation" do
      before do
        allow(Yast::Mode).to receive(:mode).and_return("installation")
      end

      it "returns 'regurl' boot parameter from Linuxrc" do
        url = "https://example.com/register"
        expect(Yast::Linuxrc).to receive(:InstallInf).with("regurl").and_return(url)
        # make sure no SLP discovery is executed, the boot parameter has higher priority
        expect(Yast::WFM).to receive(:call).with("discover_registration_services").never
        expect(Registration::UrlHelpers.registration_url).to eq(url)
      end

      it "returns the SLP server selected by user" do
        # no boot parameter passed, it would have higher priority
        expect(Yast::Linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)

        slp_url = "https://example.com/register"
        expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(slp_url)
        expect(Registration::UrlHelpers.registration_url).to eq(slp_url)
      end

      it "returns nil when the SLP dialog is canceled" do
        # no boot parameter passed, it would have higher priority
        expect(Yast::Linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)

        expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(nil)
        expect(Registration::UrlHelpers.registration_url).to be_nil
      end

      it "returns nil in other cases" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)
        expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(nil)
        expect(Registration::UrlHelpers.registration_url).to be_nil
      end
    end

    context "at installed system" do
      before do
        allow(Yast::Mode).to receive(:mode).and_return("normal")
        allow(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(nil)
        # must not ask Linuxrc at all
        expect(Yast::Linuxrc).to receive(:InstallInf).never
      end

      it "return nil (default) if config file is not present" do
        # stub config file reading
        expect(File).to receive(:exist?).with(SUSE::Connect::Config::DEFAULT_CONFIG_FILE).
          and_return(false)
        expect(Registration::UrlHelpers.registration_url).to be_nil
      end

      it "reads the URL from config file if present" do
        # stub config file reading
        url = "https://example.com"
        expect(File).to receive(:exist?).with(SUSE::Connect::Config::DEFAULT_CONFIG_FILE).
          and_return(true).twice
        expect(YAML).to receive(:load_file).and_return("url" => url, "insecure" => false)
        expect(Registration::UrlHelpers.registration_url).to eq(url)
      end
    end

    context "at upgrade" do
      let(:suse_register) { "/mnt/etc/suseRegister.conf" }

      before do
        allow(Yast::Mode).to receive(:mode).and_return("update")
        allow(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(nil)

        allow(Yast::Installation).to receive(:destdir).and_return("/mnt")
      end

      it "returns 'regurl' boot parameter from Linuxrc" do
        url = "https://example.com/register"
        expect(Yast::Linuxrc).to receive(:InstallInf).with("regurl").and_return(url)
        # make sure no SLP discovery is executed, the boot parameter has higher priority
        expect(Yast::WFM).to receive(:call).with("discover_registration_services").never
        expect(Registration::UrlHelpers.registration_url).to eq(url)
      end

      context "the system has been already registered" do
        before do
          allow(File).to receive(:exist?).with("/mnt/etc/zypp/credentials.d/NCCcredentials").and_return(true)
          expect(Yast::Linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)
        end

        it "return default when NCC registration server was used" do
          expect(File).to receive(:exist?).with(suse_register).and_return(true)
          expect(File).to receive(:readlines).with(suse_register).\
            and_return(File.readlines(fixtures_file("old_conf_ncc/etc/suseRegister.conf")))

          expect(Registration::UrlHelpers.registration_url).to be_nil
        end

        it "return URL of SMT server when used" do
          expect(File).to receive(:exist?).with(suse_register).and_return(true)
          expect(File).to receive(:readlines).with(suse_register).\
            and_return(File.readlines(fixtures_file("old_conf_custom/etc/suseRegister.conf")))

          expect(Registration::UrlHelpers.registration_url).to eq("https://myserver.com")
        end

        it "returns default URL (nil) when the old URL failed at upgrade" do
          expect(::Registration::Storage::Cache.instance).to receive(:upgrade_failed).and_return(true)
          expect(Registration::UrlHelpers.registration_url).to be_nil
        end
      end

      context "the system has not been registered" do
        before do
          expect(File).to receive(:exist?).with("/mnt/etc/zypp/credentials.d/NCCcredentials").and_return(false)
          expect(Yast::Linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)
        end

        it "calls SLP discovery" do
          slp_url = "https://slp.example.com/register"
          expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(slp_url)
          expect(Registration::UrlHelpers.registration_url).to eq(slp_url)
        end

        it "returns nil (default URL) when no SLP server is available" do
          expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(nil)
          expect(Registration::UrlHelpers.registration_url).to eq(nil)
        end
      end
    end

    context "in other modes" do
      before do
        allow(Yast::Mode).to receive(:mode).and_return("config")
      end

      it "returns nil (default URL)" do
        expect(Registration::UrlHelpers.registration_url).to be_nil
      end
    end
  end

  describe ".service_url" do
    it "converts a SLP service to plain URL" do
      url = "https://example.com/registration"
      service1 = "service:registration.suse:manager:#{url}"
      service2 = "service:registration.suse:smt:#{url}"
      expect(Registration::UrlHelpers.service_url(service1)).to eq(url)
      expect(Registration::UrlHelpers.service_url(service2)).to eq(url)
    end
  end

  describe ".credentials_from_url" do
    it "returns credentials parameter from URL" do
      url = "https://scc.suse.com/service/repo/repoindex.xml?credentials=SLES_credentials"
      expect(Registration::UrlHelpers.credentials_from_url(url)).to eq("SLES_credentials")
    end

    it "returns nil if the URL misses credentials parameter" do
      url = "https://scc.suse.com/service/repo/repoindex.xml?nocredentials=SLES_credentials"
      expect(Registration::UrlHelpers.credentials_from_url(url)).to eq(nil)
    end

    it "raises URI::InvalidURIError when URL is invalid" do
      url = ":foo:"
      expect{Registration::UrlHelpers.credentials_from_url(url)}.to raise_error(URI::InvalidURIError)
    end
  end

  describe ".reset_registration_url" do
    it "resets cached URL" do
      # set the cache
      ::Registration::Storage::Cache.instance.reg_url = "http://example.com"
      ::Registration::Storage::Cache.instance.reg_url_cached = true

      Registration::UrlHelpers.reset_registration_url

      expect(::Registration::Storage::Cache.instance.reg_url).to be_nil
      expect(::Registration::Storage::Cache.instance.reg_url_cached).to be_false
    end
  end

  describe ".slp_discovery" do
    it "returns SLP services excluding SUSE Manager services" do
      service1 = double(:slp_url => "service:registration.suse:smt:https://example.com/connect")
      service2 = double(:slp_url => "service:registration.suse:manager:https://example.com/connect")
      expect(Yast::SlpService).to receive(:all).and_return([service1, service2])

      result = Registration::UrlHelpers.slp_discovery
      expect(result).to include(service1)
      # SUSE manager service (service2) is ignored
      expect(result).to_not include(service2)
    end
  end

  describe ".slp_discovery_feedback" do
    it "runs SLP discovery with progress message" do
      services = [ double(:slp_url => "service:registration.suse:smt:https://example.com/connect") ]
      expect(Yast::SlpService).to receive(:all).and_return(services)

      # stub Popup.Feedback call but yield the passed block
      expect(Yast::Popup).to receive(:Feedback).and_yield

      expect(Registration::UrlHelpers.slp_discovery_feedback).to eql(services)
    end
  end

end
