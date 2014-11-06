#! /usr/bin/env rspec

require_relative "spec_helper"
require "registration/eula_reader"

describe Registration::EulaReader do
  subject { Registration::EulaReader.new("") }

  describe "#current_language" do
    before do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("cs_CZ.utf8")
    end
    
    it "returns the current language if there is a license for it" do
      allow(subject).to receive(:languages).and_return(["cs_CZ", "de", "en"])
      expect(subject.current_language).to eq("cs_CZ")
    end

    it "returns the country fallback if the current language is missing" do
      allow(subject).to receive(:languages).and_return(["cs", "de", "en"])
      expect(subject.current_language).to eq("cs")
    end

    it "returns 'en_US' fallback if the current language and country is missing" do
      allow(subject).to receive(:languages).and_return(["de", "en_US", "en"])
      expect(subject.current_language).to eq("en_US")
    end

    it "returns 'en' fallback if 'en_US' fallback is missing" do
      allow(subject).to receive(:languages).and_return(["de", "en"])
      expect(subject.current_language).to eq("en")
    end

    it "returns any present translation when no English fallback is found" do
      license_langs = ["de", "es", "fr"]
      allow(subject).to receive(:languages).and_return(license_langs)

      # the actual returned translation is undefined, just make sure
      # the returned language is in the list of available translations
      expect(license_langs).to include(subject.current_language)
    end
  end
end
