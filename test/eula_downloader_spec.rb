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
      index = "directory.yast\nlicense.txt\nlicense.de.txt"

      expect(Registration::Downloader).to receive(:download).\
        and_return(index, en_eula, de_eula)

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
      expect(Registration::Downloader).to receive(:download).\
        and_raise("Downloading failed")

      Dir.mktmpdir do |tmpdir|
        loader = Registration::EulaDownloader.new("http://example.com/eula", tmpdir)

        expect{loader.download}.to raise_error RuntimeError, "Downloading failed"

        # nothing saved
        expect(Dir.entries(tmpdir)).to match_array([".", ".."])
      end
    end

  end

end
