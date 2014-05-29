#! /usr/bin/env rspec

require_relative "spec_helper"
require_relative "yast_stubs"
require 'tmpdir'

describe "Registration::EulaDownloader" do

  before do
    stub_yast_require
    require "registration/eula_downloader"
  end

  describe ".download" do
    it "downloads the license with translations" do
      en_eula = "English EULA"
      de_eula = "Deutsch EULA"

      index = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(index).to receive(:body).and_return("directory.yast\nlicense.txt\nlicense.de.txt")

      license = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(license).to receive(:body).and_return(en_eula)

      license_de = Net::HTTPSuccess.new("1.1", 200, "OK")
      expect(license_de).to receive(:body).and_return(de_eula)

      # mock the responses for respective URL paths
      Net::HTTP.any_instance.stub(:request) do |request|
        case request.path
        when "/eula/directory.yast"
          index
        when "/eula/license.txt"
          license
        when "/eula/license.de.txt"
          license_de
        end
      end

      Dir.mktmpdir do |tmpdir|
        loader = Registration::EulaDownloader.new("https://example.com/eula", tmpdir)

        expect{loader.download}.not_to raise_error

        # the index file is not saved
        expect(Dir.entries(tmpdir)).to match_array([".", "..", "license.txt", "license.de.txt"])
        # check the license content
        expect(File.read(File.join(tmpdir, "license.txt"))).to eq(en_eula)
        expect(File.read(File.join(tmpdir, "license.de.txt"))).to eq(de_eula)
      end
    end

    it "it raises an exception when download fails" do
      index = Net::HTTPNotFound.new("1.1", 404, "Not Found")
      index.should_receive(:body).and_return("")

      Net::HTTP.any_instance.should_receive(:request).
        with(an_instance_of(Net::HTTP::Get)).and_return(index)

      Dir.mktmpdir do |tmpdir|
        loader = Registration::EulaDownloader.new("http://example.com/eula", tmpdir)

        expect{loader.download}.to raise_error RuntimeError,
          "Downloading http://example.com/eula/directory.yast failed: Not Found"

        # nothing saved
        expect(Dir.entries(tmpdir)).to match_array([".", ".."])
      end
    end
  end

end
