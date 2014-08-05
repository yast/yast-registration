#! /usr/bin/env rspec

require_relative "spec_helper"
require_relative "yast_stubs"
require 'tmpdir'

describe "Registration::Downloader" do
  before do
    stub_yast_require
    require "registration/downloader"
  end

  let(:url) { "http://example.com" }

  describe ".download" do
    it "downloads the file" do
      index = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(index).to receive(:body).and_return("response")

      Net::HTTP.any_instance.should_receive(:request).
        with(an_instance_of(Net::HTTP::Get)).and_return(index)

      expect(Registration::Downloader.download(url)).to eq("response")
    end

    it "uses secure connection for HTTPS URL" do
      index = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(index).to receive(:body).and_return("response")

      Net::HTTP.any_instance.should_receive(:request).
        with(an_instance_of(Net::HTTP::Get)).and_return(index)

      # check for HTTPS setup
      Net::HTTP.any_instance.should_receive(:use_ssl=).with(true)
      Net::HTTP.any_instance.should_receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)

      https_url = "https://example.com"
      expect(Registration::Downloader.download(https_url)).to eq("response")
    end

    it "it raises an exception when download fails" do
      index = Net::HTTPNotFound.new("1.1", 404, "Not Found")
      expect(index).to receive(:body).and_return("")

      Net::HTTP.any_instance.should_receive(:request).
        with(an_instance_of(Net::HTTP::Get)).and_return(index)

      expect{Registration::Downloader.download(url)}.to raise_error RuntimeError,
        "Downloading #{url} failed: Not Found"
    end

    it "handles HTTP redirection" do
      index1 = Net::HTTPRedirection.new("1.1", 302, "Found")
      index1["location"] = "http://redirected.example.com"

      index2 = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(index2).to receive(:body).and_return("response")

      http = double()
      expect(Net::HTTP).to receive(:new).twice.and_return(http)
      expect(http).to receive(:request).twice.and_return(index1, index2)

      expect(Registration::Downloader.download(url)).to eq("response")
    end
  end

end
