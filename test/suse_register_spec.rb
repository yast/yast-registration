#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::SuseRegister do
  subject { Registration::SuseRegister }

  describe ".new" do
    it "create new instance with /etc/suseRegister.conf from target root" do
      expect(subject.new("/")).to be_a(Registration::SuseRegister)
    end
  end

  describe "#found?" do
    it "returns false if file not found" do
      root = fixtures_file("old_conf_noreg")
      reg = subject.new(root)
      expect(reg.found?).to be_false
    end

    it "returns false if file do not contain url key" do
      root = fixtures_file("old_conf_nourl")
      reg = subject.new(root)
      expect(reg.found?).to be_false
    end

    it "returns true if file found and contain url key" do
      root = fixtures_file("old_conf_ncc")
      reg = subject.new(root)
      expect(reg.found?).to be_true
    end
  end

  describe "#ncc?" do
    it "returns false if file not found" do
      root = fixtures_file("old_conf_noreg")
      reg = subject.new(root)
      expect(reg.ncc?).to be_false
    end

    it "returns false if file contain custom url" do
      root = fixtures_file("old_conf_custom")
      reg = subject.new(root)
      expect(reg.ncc?).to be_false
    end

    it "returns true if file contain ncc url" do
      root = fixtures_file("old_conf_ncc")
      reg = subject.new(root)
      expect(reg.ncc?).to be_true
    end
  end

  describe "#stripped_url" do
    it "return url without ending path for old registration protocol" do
      root = fixtures_file("old_conf_custom")
      reg = subject.new(root)
      expect(reg.stripped_url.to_s).to eq("https://myserver.com")
    end
  end
end
