#! /usr/bin/env rspec
# typed: false

require_relative "spec_helper"
require "tmpdir"

describe "Registration::Downloader" do
  let(:url) { "http://example.com" }

  describe ".download" do
    it "downloads the file" do
      index = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(index).to receive(:body).and_return("response")

      expect_any_instance_of(Net::HTTP).to receive(:request)
        .with(an_instance_of(Net::HTTP::Get)).and_return(index)
      expect_any_instance_of(Net::HTTP).to receive(:proxy?).and_return(false)

      expect(Registration::Downloader.download(url)).to eq("response")
    end

    it "uses secure connection for HTTPS URL" do
      index = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(index).to receive(:body).and_return("response")

      expect_any_instance_of(Net::HTTP).to receive(:request)
        .with(an_instance_of(Net::HTTP::Get)).and_return(index)

      # check for HTTPS setup
      expect_any_instance_of(Net::HTTP).to receive(:use_ssl=).with(true)
      expect_any_instance_of(Net::HTTP).to receive(:verify_mode=)
        .with(OpenSSL::SSL::VERIFY_PEER)
      expect_any_instance_of(Net::HTTP).to receive(:proxy?).and_return(false)

      https_url = "https://example.com"
      expect(Registration::Downloader.download(https_url)).to eq("response")
    end

    it "it raises an exception when download fails" do
      index = Net::HTTPNotFound.new("1.1", 404, "Not Found")
      expect(index).to receive(:body).and_return("")

      expect_any_instance_of(Net::HTTP).to receive(:request)
        .with(an_instance_of(Net::HTTP::Get)).and_return(index)
      expect_any_instance_of(Net::HTTP).to receive(:proxy?).and_return(false)

      expect { Registration::Downloader.download(url) }.to raise_error(
        Registration::DownloadError, "Downloading #{url} failed: Not Found"
      )
    end

    it "handles HTTP redirection" do
      index1 = Net::HTTPRedirection.new("1.1", 302, "Found")
      index1["location"] = "http://redirected.example.com"

      index2 = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(index2).to receive(:body).and_return("response")

      http = double
      expect(Net::HTTP).to receive(:new).twice.and_return(http)
      expect(http).to receive(:request).twice.and_return(index1, index2)
      expect(http).to receive(:proxy?).twice.and_return(false)

      expect(Registration::Downloader.download(url)).to eq("response")
    end

    it "can block HTTP redirection" do
      index = Net::HTTPRedirection.new("1.1", 302, "Found")
      index["location"] = "http://redirected.example.com"

      http = double
      expect(Net::HTTP).to receive(:new).and_return(http)
      expect(http).to receive(:request).and_return(index)
      expect(http).to receive(:proxy?).and_return(false)
      expect { Registration::Downloader.download(url, allow_redirect: false) }.to raise_error(
        Registration::DownloadError, "Redirection not allowed or limit has been reached"
      )
    end

    it "reads proxy credentials when proxy is used" do
      user = "proxy_user"
      password = "proxy_password"
      index = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(index).to receive(:body).and_return("response")

      expect_any_instance_of(Net::HTTP).to receive(:request)
        .with(an_instance_of(Net::HTTP::Get)).and_return(index)
      expect_any_instance_of(Net::HTTP).to receive(:proxy?).and_return(true)
      expect_any_instance_of(SUSE::Toolkit::CurlrcDotfile).to receive(:username)
        .and_return(user)
      expect_any_instance_of(SUSE::Toolkit::CurlrcDotfile).to receive(:password)
        .and_return(password)
      expect_any_instance_of(Net::HTTP).to receive(:proxy_user=).with(user)
      expect_any_instance_of(Net::HTTP).to receive(:proxy_pass=).with(password)

      expect(Registration::Downloader.download(url)).to eq("response")
    end
  end
end
