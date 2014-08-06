#! /usr/bin/env rspec

require_relative "spec_helper"
require_relative "yast_stubs"

describe "Registration::UrlHelpers" do
  let(:yast_wfm) { double("Yast::WFM") }

  before do
    stub_yast_require
    require "registration/url_helpers"
    stub_const("Yast::WFM", yast_wfm)
  end

  describe ".registration_url" do
    let(:yast_mode) { double("Yast::Mode") }
    let(:yast_linuxrc) { double("Yast::Linuxrc") }

    before do
      stub_const("Yast::Mode", yast_mode)
      stub_const("Yast::Linuxrc", yast_linuxrc)
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
          expect(Registration::UrlHelpers.registration_url).to eq(url)
        end

        it "returns nil when no custom URL is required in Linuxrc" do
          expect(yast_linuxrc).to receive(:InstallInf).with("regurl").and_return(nil)
          expect(yast_wfm).to receive(:call).with("discover_registration_services").and_return(nil)
          expect(Registration::UrlHelpers.registration_url).to be_nil
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
          expect(Registration::UrlHelpers.registration_url).to eq(slp_url)
        end

        it "returns nil when the SLP dialog is canceled" do
          expect(yast_wfm).to receive(:call).with("discover_registration_services").and_return(nil)
          expect(Registration::UrlHelpers.registration_url).to be_nil
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
        expect(Registration::UrlHelpers.registration_url).to be_nil
      end

      it "reads the URL from config file if present" do
        # must not ask Linuxrc at all
        expect(yast_linuxrc).to receive(:InstallInf).never
        # stub config file reading
        url = "https://example.com"
        expect_any_instance_of(SUSE::Connect::Config).to receive(:url).twice.and_return(url)
        expect(Registration::UrlHelpers.registration_url).to eq(url)
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
        expect(Registration::UrlHelpers.registration_url).to eq(url)
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

          expect(Registration::UrlHelpers.registration_url).to be_nil
        end

        it "return URL of SMT server when used" do
          expect(File).to receive(:exist?).with(suse_register).and_return(true)
          expect(File).to receive(:readlines).with(suse_register).\
            and_return(File.readlines(fixtures_file("old_conf_custom/etc/suseRegister.conf")))

          expect(Registration::UrlHelpers.registration_url).to eq("https://myserver.com")
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
          expect(Registration::UrlHelpers.registration_url).to eq(slp_url)
        end
      end
    end

    context "at unknown mode" do
      before do
        allow(yast_mode).to receive(:mode).and_return("config")
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

end
