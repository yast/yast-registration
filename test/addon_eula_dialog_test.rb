#! /usr/bin/env rspec

require_relative "spec_helper"
require "registration/ui/addon_eula_dialog"

describe Registration::UI::AddonEulaDialog do
  subject { Registration::UI::AddonEulaDialog }

  describe "#eula_lang" do
    it "returns the current language if there is a license for it" do
      # one call is hidden in the FastGettext initialization call
      # (textdomain "registration") in #initialize
      expect(Yast::WFM).to receive(:GetLanguage).and_return("cs_CZ.utf8").twice
      license_langs = [ "cs_CZ", "de", "en" ]

      expect(subject.new([]).send(:eula_lang, license_langs)).
        to eq("cs_CZ")
    end

    it "returns the country fallback if the current language is missing" do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("cs_CZ.utf8").twice
      license_langs = [ "cs", "de", "en" ]

      expect(subject.new([]).send(:eula_lang, license_langs)).
        to eq("cs")
    end

    it "returns 'en_US' fallback if the current language and country is missing" do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("cs_CZ.utf8").twice
      license_langs = [ "de", "en_US", "en" ]

      expect(subject.new([]).send(:eula_lang, license_langs)).
        to eq("en_US")
    end

    it "returns 'en' fallback if 'en_US' fallback is missing" do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("cs_CZ.utf8").twice
      license_langs = [ "de", "en" ]

      expect(subject.new([]).send(:eula_lang, license_langs)).
        to eq("en")
    end

    it "returns any present translation when no English fallback is found" do
      expect(Yast::WFM).to receive(:GetLanguage).and_return("cs_CZ.utf8").twice
      license_langs = [ "de", "es", "fr" ]

      # the actual returned translation is undefined, just make sure
      # the returned language is in the list of available translations
      expect(license_langs).to include(subject.new([]).send(:eula_lang, license_langs))
    end
  end
end
