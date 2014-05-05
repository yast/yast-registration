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
      ::Registration::Storage::Cache.instance.reg_url = nil
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

        # FIXME: stub SLP service discovery, later add config file reading
        expect(yast_wfm).to receive(:call).with("discover_registration_services").and_return(nil)
      end

      it "ignores Linuxrc boot parameters" do
        # must not ask Linuxrc at all
        expect(yast_linuxrc).to receive(:InstallInf).never
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

end
