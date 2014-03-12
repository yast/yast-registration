#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/helpers"

describe Registration::Helpers do

  describe ".registration_url" do
    context "at installation" do
      before do
        allow(Yast::Mode).to receive(:installation).and_return(true)
      end

      context "no local registration server is announced via SLP" do
        it "returns 'reg_url' boot parameter from Linuxrc" do
          url = "https://example.com/register"
          expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("splash=silent reg_url=#{url} vga=0x314")
          # make sure no SLP discovery is executed, the boot parameter has higher priority
          expect(Yast::WFM).to receive(:call).with("discover_registration_services").never
          expect(Registration::Helpers.registration_url).to eq(url)
        end

        it "uses the last 'reg_url' boot parameter from Linuxrc" do
          url1 = "https://example.com/register"
          url2 = "https://foo.org/registration"
          expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("splash=silent reg_url=#{url1} reg_url=#{url2} vga=0x314")
          # make sure no SLP discovery is executed, the boot parameter has higher priority
          expect(Yast::WFM).to receive(:call).with("discover_registration_services").never
          expect(Registration::Helpers.registration_url).to eq(url2)
        end

        it "returns nil when no custom URL is required in Linuxrc" do
          expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("splash=silent vga=0x314")
          expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(nil)
          expect(Registration::Helpers.registration_url).to be_nil
        end

        it "returns nil when no boot command line is defined in Linuxrc" do
          expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return(nil)
          expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(nil)
          expect(Registration::Helpers.registration_url).to be_nil
        end
      end

      context "no boot parameter is used and a SLP server is announced" do
        before do
          # no boot parameter passed, it would have higher priority
          expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("splash=silent vga=0x314")
        end

        it "returns the SLP server selected by user" do
          slp_url = "https://example.com/register"
          expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(slp_url)
          expect(Registration::Helpers.registration_url).to eq(slp_url)
        end

        it "returns nil when the SLP dialog is canceled" do
          expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(nil)
          expect(Registration::Helpers.registration_url).to be_nil
        end

      end
    end

    context "at installed system" do
      before do
        allow(Yast::Mode).to receive(:installation).and_return(false)
        # FIXME: stub SLP service discovery, later add config file reading
        expect(Yast::WFM).to receive(:call).with("discover_registration_services").and_return(nil)
      end

      it "ignores Linuxrc boot parameters" do
        # must not ask Linuxrc at all
        expect(Yast::Linuxrc).to receive(:InstallInf).never
        expect(Registration::Helpers.registration_url).to be_nil
      end
    end
  end

  describe ".service_url" do
    it "converts a SLP service to plain URL" do
      url = "https://example.com/registration"
      service = "service:susemanager:#{url}"
      expect(Registration::Helpers.service_url(service)).to eq(url)
    end
  end

  describe ".service_description" do
    let(:slp_url) { "https://example.com/registration" }
    let(:slp_attributes) { double }
    let(:slp_service) { double }

    before do
      expect(slp_service).to receive(:attributes).and_return(slp_attributes)
      expect(slp_service).to receive(:slp_url).and_return("service:susemanager:#{slp_url}")
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

end
