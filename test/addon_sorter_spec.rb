#! /usr/bin/env rspec

require_relative "spec_helper"

require "yaml"
require "registration/addon"
require "registration/addon_sorter"

describe "Registration::ADDON_SORTER" do
  let(:available_addons) { YAML.load_file(fixtures_file("available_addons.yml")) }
  let(:unknown_addons) { YAML.load_file(fixtures_file("available_unknown_addons.yml")) }

  it "sorts the addons in display order" do
    expected = ["sle-ha", "sle-ha-geo", "sle-sdk", "sle-we",
      "sle-module-adv-systems-management", "sle-module-legacy",
      "sle-module-public-cloud", "sle-module-web-scripting"]

    expect(available_addons.sort(&Registration::ADDON_SORTER).map(&:identifier)).to eql(expected)
  end

  it "moves the unknown product types at the end" do
    # AdvMgmt and Legacy have undefined type => at the end
    expected = ["sle-sdk", "sle-we", "sle-module-public-cloud",
      "sle-module-web-scripting", "sle-module-legacy",
      "sle-module-adv-systems-management"]

    expect(unknown_addons.sort(&Registration::ADDON_SORTER).map(&:identifier)).to eql(expected)
  end

end
