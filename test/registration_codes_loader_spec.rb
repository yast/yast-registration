#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::RegistrationCodesLoader do
  class RegistrationCodesLoaderTest
    include Registration::RegistrationCodesLoader
  end

  subject { RegistrationCodesLoaderTest.new }

  describe "#reg_codes_from_usb_stick" do
    let(:tempfile) { "/whatever1" }
    let(:xmlname)  { "regcodes.xml" }
    let(:txtname)  { "regcodes.txt" }

    before do
      expect(subject).to receive(:with_tempfile) do |_pattern, &block|
        block.call(tempfile)
      end
    end

    context "when only regcodes.xml exists" do
      it "delegates to reg_codes_from_xml" do
        expect(subject).to receive(:get_file_from_url)
          .with(scheme: "usb", host: "", urlpath: "/#{xmlname}",
                               localfile: tempfile,
                               urltok: {}, destdir: "")
          .and_return(true)

        expect(subject).to receive(:reg_codes_from_xml)
          .with(tempfile)
          .and_return("a" => "b")

        expect(subject.reg_codes_from_usb_stick).to eq("a" => "b")
      end
    end

    context "when only regcodes.txt exists" do
      it "delegates to reg_codes_from_txt" do
        expect(subject).to receive(:get_file_from_url)
          .with(scheme: "usb", host: "", urlpath: "/#{xmlname}",
                               localfile: tempfile,
                               urltok: {}, destdir: "")
          .and_return(false)

        expect(subject).to receive(:get_file_from_url)
          .with(scheme: "usb", host: "", urlpath: "/#{txtname}",
                               localfile: tempfile,
                               urltok: {}, destdir: "")
          .and_return(true)

        expect(subject).to receive(:reg_codes_from_txt)
          .with(tempfile)
          .and_return("b" => "c")

        expect(subject.reg_codes_from_usb_stick).to eq("b" => "c")
      end
    end

    context "when both regcodes.xml, regcodes.txt exist" do
      it "delegates to reg_codes_from_xml" do
        allow(subject).to receive(:get_file_from_url)
          .with(scheme: "usb", host: "", urlpath: "/#{xmlname}",
                               localfile: tempfile,
                               urltok: {}, destdir: "")
          .and_return(true)
        allow(subject).to receive(:get_file_from_url)
          .with(scheme: "usb", host: "", urlpath: "/#{txtname}",
                               localfile: tempfile,
                               urltok: {}, destdir: "")
          .and_return(true)

        expect(subject).to receive(:reg_codes_from_xml)
          .with(tempfile)
          .and_return("a" => "b")

        expect(subject.reg_codes_from_usb_stick).to eq("a" => "b")
      end
    end

    context "when neither regcodes.* exists" do
      it "returns nil" do
        expect(subject).to receive(:get_file_from_url)
          .with(scheme: "usb", host: "", urlpath: "/#{xmlname}",
                               localfile: tempfile,
                               urltok: {}, destdir: "")
          .and_return(false)

        expect(subject).to receive(:get_file_from_url)
          .with(scheme: "usb", host: "", urlpath: "/#{txtname}",
                               localfile: tempfile,
                               urltok: {}, destdir: "")
          .and_return(false)

        expect(subject.reg_codes_from_usb_stick).to eq(nil)
      end
    end
  end

  describe "#reg_codes_from_xml" do
    let(:valid_fixture_codes) do
      {
        "SLES"              => "cc36aae1",
        "SLED"              => "309105d4",
        "sle-we"            => "5eedd26a",
        "sle-live-patching" => "8c541494"
      }
    end

    it "returns nil if file not found" do
      expect(subject.reg_codes_from_xml("/tmp/nosuchfile")).to eq(nil)
    end

    it "returns nil if file not readable" do
      expect(subject.reg_codes_from_xml("/etc")).to eq(nil)
    end

    it "parses a valid fixture" do
      filename = fixtures_file("regcodes.xml")
      expect(subject.reg_codes_from_xml(filename)).to eq(valid_fixture_codes)
    end
  end

  describe "#reg_codes_from_txt" do
    let(:valid_fixture_codes) do
      {
        "SLES"              => "cc360000",
        "SLED"              => "30910000",
        "sle-we"            => "5eed0000",
        "sle-live-patching" => "8c540000"
      }
    end

    it "returns nil if file not found" do
      expect(subject.reg_codes_from_txt("/tmp/nosuchfile")).to eq(nil)
    end

    it "returns nil if file not readable" do
      expect(subject.reg_codes_from_txt("/etc")).to eq(nil)
    end

    it "parses a valid fixture" do
      filename = fixtures_file("regcodes.txt")
      expect(subject.reg_codes_from_txt(filename)).to eq(valid_fixture_codes)
    end

    it "parses a valid fixture with CRLF" do
      filename = fixtures_file("regcodes_crlf.txt")
      expect(subject.reg_codes_from_txt(filename)).to eq(valid_fixture_codes)
    end
  end
end
