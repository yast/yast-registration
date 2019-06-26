#! /usr/bin/env rspec
# typed: false

require_relative "spec_helper"
require "registration/eula_reader"

describe Registration::EulaReader do
  # trick: "" is used to avoid mocking license reading, it does not read anything
  subject { Registration::EulaReader.new("") }

  describe "#current_language" do
    before do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("cs_CZ.utf8")
    end

    it "returns the current language if there is a license for it" do
      allow(subject).to receive(:licenses).and_return("cs_CZ" => "", "de" => "", "en" => "")
      expect(subject.current_language).to eq("cs_CZ")
    end

    it "returns the country fallback if the current language is missing" do
      allow(subject).to receive(:licenses).and_return("cs" => "", "de" => "", "en" => "")
      expect(subject.current_language).to eq("cs")
    end

    it "returns 'en_US' fallback if the current language and country is missing" do
      allow(subject).to receive(:licenses).and_return("de" => "", "en_US" => "", "en" => "")
      expect(subject.current_language).to eq("en_US")
    end

    it "returns 'en' fallback if 'en_US' fallback is missing" do
      allow(subject).to receive(:licenses).and_return("de" => "", "en" => "")
      expect(subject.current_language).to eq("en")
    end

    it "returns any present translation when no English fallback is found" do
      allow(subject).to receive(:licenses).and_return("de" => "", "es" => "", "fr" => "")

      # the current implementation returns the first item from the sorted list
      # which is "de" in this case
      expect(subject.current_language).to eq("de")
    end
  end
end
