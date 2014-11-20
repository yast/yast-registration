#! /usr/bin/env rspec

require_relative "spec_helper"

describe "Registration::SmtStatus" do
  let(:url) { "https://example.com" }
  subject { Registration::SmtStatus.new(url) }

  describe "#ncc_api_present?" do
    let(:expected_url) { URI("#{url}/center/regsvc?command=listproducts") }

    it "returns true when /center/regsvc?command=listproducts returns OK" do
      expect(Registration::Downloader).to receive(:download).
        with(expected_url, insecure: false).
        and_return(true)

      expect(subject.ncc_api_present?).to be_true
    end

    it "returns false otherwise" do
      expect(Registration::Downloader).to receive(:download).
        with(expected_url, insecure: false).
        and_raise(Registration::DownloadError)

      expect(subject.ncc_api_present?).to be_false
    end
  end

end
