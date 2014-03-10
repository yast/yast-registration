#! /usr/bin/env rspec

require_relative "spec_helper"

require "yast"

require "registration/repo_state"

describe "scc_finish client" do
  let(:pkg) { double("Yast::Pkg") }

  before do
    stub_const("Yast::Pkg", pkg)
  end

  context "with Info parameter" do
    it "describes the client" do
      # check for the hash keys present
      expect(Yast::WFM.call("scc_finish", ["Info"])).to include("steps", "title", "when")
    end
  end

  context "with Write parameter" do
    it "restores the original repository states" do
      Registration::RepoStateStorage.instance.repositories = [
        Registration::RepoState.new(1, true),
        Registration::RepoState.new(2, false)
      ]

      expect(pkg).to receive(:SourceSetEnabled).with(1, true)
      expect(pkg).to receive(:SourceSetEnabled).with(2, false)
      expect(pkg).to receive(:SourceSaveAll)

      expect(Yast::WFM.call("scc_finish", ["Write"])).to be_nil
    end

    it "does not do write anything if no repo was changed" do
      Registration::RepoStateStorage.instance.repositories = []

      expect(pkg).to receive(:SourceSetEnabled).never
      expect(pkg).to receive(:SourceSaveAll).never

      expect(Yast::WFM.call("scc_finish", ["Write"])).to be_nil
    end
  end

  context "without any parameter" do
    it "the client call returns false" do
      expect(pkg).to receive(:SourceSetEnabled).never
      expect(pkg).to receive(:SourceSaveAll).never

      # WFM.call catches all exceptions and returns false
      # see https://github.com/yast/yast-ruby-bindings/blob/master/src/ruby/yast/wfm.rb#L195
      expect(Yast::WFM.call("scc_finish")).to be_false
      expect(Yast::WFM.call("scc_finish", [])).to be_false
    end
  end

  context "with a wrong parameter" do
    it "the client call returns false" do
      expect(pkg).to receive(:SourceSetEnabled).never
      expect(pkg).to receive(:SourceSaveAll).never

      expect(Yast::WFM.call("scc_finish", ["Invallid_Parameter"])).to be_false
    end
  end
end
