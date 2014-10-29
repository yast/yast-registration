#! /usr/bin/env rspec

require_relative "spec_helper"

describe "Registration::SslCertificateDetails" do
  subject do
    Registration::SslCertificateDetails.new(
      Registration::SslCertificate.load_file(fixtures_file("test.pem")))
  end
  
  let(:identity) do
    <<EOS
Common Name (CN): linux-1hyn
Organization (O): WebYaST
Organization Unit (OU): WebYaST
EOS
  end

  describe ".#subject" do
    it "returns textual summary of the certificate subject" do
      expect(subject.subject).to eq(identity)
    end
  end

  describe "#issuer" do
    it "return textual summary of the certificate issuer" do
      expect(subject.issuer).to eq(identity)
    end
  end

  describe "#summary" do
    it "returns textual summary of the whole certificate" do
      expect(subject.summary).to eq(<<EOS.chomp
Certificate:
Issued To
#{identity}
Issued By
#{identity}
SHA1 Fingerprint: 
   A8:DE:08:B1:57:52:FE:70:DF:D5:31:EA:E3:53:BB:39:EE:01:FF:B9
SHA256 Fingerprint: 
   2A:02:DA:EC:A9:FF:4C:B4:A6:C0:57:08:F6:1C:8B:B0:94:FA:F4:60:96:5E:18:48:CA:84:81:48:60:F3:CB:BF
EOS
      )
    end

    it "can optionaly limit line lenght to fit terminal width" do
      # the longest line still fits 80 chars wide terminal
      expect(subject.summary(small_space: true).split("\n").map(&:size).max).to be < 80
    end
  end
  
  
  describe "#richtext_summary" do
    it "returns rich text summary of the whole certificate" do
      result = subject.richtext_summary
      expect(result).to include("WebYaST")
      expect(result).to include("A8:DE:08:B1:57:52:FE:70:DF:D5:31:EA:E3:53:BB:39:EE:01:FF:B9")
      expect(result).to include(
        "2A:02:DA:EC:A9:FF:4C:B4:A6:C0:57:08:F6:1C:8B:B0:94:FA:F4:60:96:5E:18:48:CA:84:81:48:60:F3:CB:BF"
      )
    end
  end


end
