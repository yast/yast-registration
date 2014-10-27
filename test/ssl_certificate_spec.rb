#! /usr/bin/env rspec

require_relative "spec_helper"
require "registration/ssl_certificate"

describe "Registration::SslCertificate" do
  subject { Registration::SslCertificate.load_file(fixtures_file("test.pem")) }
  # use "openssl x509 -in test.pem -noout -serial -fingerprint" to get serial and SHA1
  # use "openssl x509 -outform der -in test.pem -out test.der" and then
  #   "sha224sum test.der" and "sha256sum test.der" to get SHA224 and SHA256
  let(:serial) { "B8:AB:F1:73:E4:1F:10:4D" }
  let(:sha1)   { "A8:DE:08:B1:57:52:FE:70:DF:D5:31:EA:E3:53:BB:39:EE:01:FF:B9" }
  let(:sha224) { "CA:F3:9F:48:18:93:52:19:78:5B:08:C7:36:CE:8A:7C:18:5D:33:0E:E3:9A:E9:44:51:EB:F8:5A" }
  let(:sha256) { "2A:02:DA:EC:A9:FF:4C:B4:A6:C0:57:08:F6:1C:8B:B0:94:FA:F4:60:96:5E:18:48:CA:84:81:48:60:F3:CB:BF" }

  describe ".load_file" do
    it "loads SSL certificate from a file" do
      expect(subject).to be_a(Registration::SslCertificate)
    end
  end

  describe ".load" do
    it "loads SSL certificate from data" do
      expect(Registration::SslCertificate.load(File.read(fixtures_file("test.pem")))).to \
        be_a(Registration::SslCertificate)
    end
  end

  describe ".download" do
    it "downloads a SSL certificate from server" do
      expect(Registration::Downloader).to receive(:download).\
        and_return(File.read(fixtures_file("test.pem")))

      expect(Registration::SslCertificate.download("http://example.com/smt.crt")).to \
        be_a(Registration::SslCertificate)
    end
  end

  describe "#fingerprint" do
    it "returns SHA1 fingerprint in HEX format" do
      expect(subject.fingerprint(Registration::Fingerprint::SHA1).value).to eq(sha1)
    end

    it "returns SHA256 fingerprint in HEX format" do
      expect(subject.fingerprint(Registration::Fingerprint::SHA256).value).to eq(sha256)
    end

    it "raises an exception when unsupported sum is requested" do
      expect{ subject.fingerprint("SHA224") }.to raise_error(/Unsupported checksum type/)
    end
  end

  describe "#serial" do
    it "returns serial number in HEX format" do
      expect(subject.serial).to eq(serial)
    end
  end

  describe "#issued_on" do
    it "returns date of issue in human readable form" do
      expect(subject.issued_on).to eq("2014-04-24")
    end
  end

  describe "#expires_on" do
    it "returns date of issue in human readable form" do
      expect(subject.expires_on).to eq("2017-04-23")
    end
  end

  context "current date in the past" do
    before do
      expect(Time).to receive(:now).and_return(Time.new(2010, 1, 1))
    end
    
    describe "#expired?" do
      it "returns false" do
        expect(subject.expired?).to be_false
      end
    end

    describe "#valid_yet?" do
      it "returns false" do
        expect(subject.valid_yet?).to be_false
      end
    end
  end

  context "current date in the future" do
    before do
      expect(Time).to receive(:now).and_return(Time.new(2020, 1, 1))
    end

    describe "#expired?" do
      it "returns true" do
        expect(subject.expired?).to be_true
      end
    end

    describe "#valid_yet?" do
      it "returns true" do
        expect(subject.valid_yet?).to be_true
      end
    end
  end

  context "current date in valid range" do
    before do
      expect(Time).to receive(:now).and_return(Time.new(2015, 1, 1))
    end

    describe "#expired?" do
      it "returns false" do
        expect(subject.expired?).to be_false
      end
    end

    describe "#valid_yet?" do
      it "returns true" do
        expect(subject.valid_yet?).to be_true
      end
    end
  end

  describe "#subject_name" do
    it "returns subject name" do
      expect(subject.subject_name).to eq("linux-1hyn")
    end
  end

  describe "#subject_organization" do
    it "returns subject organization name" do
      expect(subject.subject_organization).to eq("WebYaST")
    end
  end

  describe "#subject_organization_unit" do
    it "returns subject organization unit name" do
      expect(subject.subject_organization_unit).to eq("WebYaST")
    end
  end

  describe "#issuer_name" do
    it "returns issuer name" do
      expect(subject.issuer_name).to eq("linux-1hyn")
    end
  end

  describe "#issuer_organization" do
    it "returns issuer organization name" do
      expect(subject.issuer_organization).to eq("WebYaST")
    end
  end

  describe "#issuer_organization_unit" do
    it "returns issuer organization unit name" do
      expect(subject.issuer_organization_unit).to eq("WebYaST")
    end
  end

  describe "#import_to_system" do
    it "imports the certificate to the system" do
      expect(SUSE::Connect::YaST).to receive(:import_certificate) \
        .with(an_instance_of(OpenSSL::X509::Certificate))

      subject.import_to_system
    end
  end

end
