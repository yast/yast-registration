#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/helpers"

describe Registration::Helpers do

  describe ".registration_url" do
    context "at installation" do
      before do
        expect(Yast::Mode).to receive(:installation).and_return(true)
      end

      it "returns 'reg_url' boot parameter from Linuxrc" do
        url = "https://example.com/register"
        expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("splash=silent reg_url=#{url} vga=0x314")
        expect(Registration::Helpers.registration_url).to eq(url)
      end

      it "uses the last 'reg_url' boot parameter from Linuxrc" do
        url1 = "https://example.com/register"
        url2 = "https://foo.org/registration"
        expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("splash=silent reg_url=#{url1} reg_url=#{url2} vga=0x314")
        expect(Registration::Helpers.registration_url).to eq(url2)
      end

      it "returns nil when no custom URL is required in Linuxrc" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("splash=silent vga=0x314")
        expect(Registration::Helpers.registration_url).to be_nil
      end

      it "returns nil when no boot command line is defined in Linuxrc" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return(nil)
        expect(Registration::Helpers.registration_url).to be_nil
      end
    end

    context "at installed system" do
      before do
        expect(Yast::Mode).to receive(:installation).and_return(false)
      end

      it "ignores Linuxrc boot parameters" do
        # must not ask Linuxrc at all
        expect(Yast::Linuxrc).to receive(:InstallInf).never
        expect(Registration::Helpers.registration_url).to be_nil
      end
    end
  end

end
