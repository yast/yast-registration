#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/helpers"

Yast.import "SlpService"

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

end
