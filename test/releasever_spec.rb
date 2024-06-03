#! /usr/bin/env rspec

require_relative "spec_helper"
require "yaml"

describe Registration::Releasever do
  let(:version) { "42" }
  let(:repo) { 7 }
  subject { Registration::Releasever.new(version) }

  describe "#activate" do
    before do
      allow(Yast::Pkg).to receive(:SourceFinishAll)
      allow(Yast::Pkg).to receive(:SourceRestore)
      allow(Yast::Pkg).to receive(:SourceLoad)
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([repo])
      allow(ENV).to receive(:[]=).with("ZYPP_REPO_RELEASEVER", version)
    end

    it "exports the new $releasever value in the environment" do
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(repo)
        .and_return("raw_url" => "https://example.com/SLES")
      expect(ENV).to receive(:[]=).with("ZYPP_REPO_RELEASEVER", version)
      subject.activate
    end

    it "refreshes the repositories containing $releasever in the URL" do
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(repo)
        .and_return("raw_url" => "https://example.com/SLES/$releasever")
      expect(Yast::Pkg).to receive(:SourceForceRefreshNow).with(repo)
      subject.activate
    end

    it "refreshes the repositories containing a complex $releasever in the URL" do
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(repo)
        .and_return("raw_url" => "https://example.com/SLE_${releasever}")
      expect(Yast::Pkg).to receive(:SourceForceRefreshNow).with(repo)
      subject.activate
    end

    # some complex test case (see bsc#944505#c0):
    # SLE_${releasever_major}${releasever_minor:+_SP$releasever_minor}
    it "refreshes the repositories containing an expression in the URL" do
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(repo).and_return(
        "raw_url" => "https://example.com/SLE_${releasever_major}" \
          "${releasever_minor:+_SP$releasever_minor}"
      )
      expect(Yast::Pkg).to receive(:SourceForceRefreshNow).with(repo)
      subject.activate
    end

    it "skips repository reload if $releasever is not used in any repository" do
      expect(Yast::Pkg).to_not receive(:SourceFinishAll)
      expect(Yast::Pkg).to_not receive(:SourceRestore)
      expect(Yast::Pkg).to_not receive(:SourceLoad)
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(repo)
        .and_return("raw_url" => "https://example.com/")
      expect(Yast::Pkg).to_not receive(:SourceForceRefreshNow)
      subject.activate
    end
  end

  describe ".set?" do
    it "returns false if the $releasever has not been set" do
      expect(ENV).to receive(:[]).with("ZYPP_REPO_RELEASEVER").and_return(nil)
      expect(Registration::Releasever.set?).to eq(false)
    end

    it "returns true if the $releasever has been set" do
      expect(ENV).to receive(:[]).with("ZYPP_REPO_RELEASEVER").and_return("42")
      expect(Registration::Releasever.set?).to eq(true)
    end
  end
end
