#! /usr/bin/env rspec

require_relative "spec_helper"

require "yaml"
require "registration/addon"
require "registration/addon_sorter"

describe "Registration::ADDON_SORTER" do
  let(:available_addons) { YAML.load_file(fixtures_file("available_addons.yml")) }

  it "sorts the addons in display order" do
    expected = ["sle-hae", "sle-ha-geo", "sle-sdk", "sle-we",
      "sle-module-adv-systems-management", "sle-module-legacy",
      "sle-module-public-cloud", "sle-module-web-scripting"]

    expect(available_addons.sort(&Registration::ADDON_SORTER).map(&:identifier)).to eql(expected)
  end

end
