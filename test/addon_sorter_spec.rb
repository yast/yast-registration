#! /usr/bin/env rspec

require_relative "spec_helper"
require "yaml"

describe "Registration::ADDON_SORTER" do
  let(:available_addons) { load_yaml_fixture("available_addons.yml") }
  let(:unknown_addons) { load_yaml_fixture("available_unknown_addons.yml") }

  it "sorts the addons in display order" do
    if RUBY_VERSION.start_with?("3.0.")
      pending "YaML loading of older OpenStruct is broken in ruby 3.0"
    end

    expected = [
      "SUSE Cloud for SLE 12 Compute Nodes 5 x86_64",
      "SUSE Enterprise Storage 1 x86_64",
      "SUSE Enterprise Storage 2 x86_64",
      "SUSE Linux Enterprise High Availability Extension 12 x86_64",
      "SUSE Linux Enterprise High Availability GEO Extension 12 x86_64",
      "SUSE Linux Enterprise Live Patching 12 x86_64",
      "SUSE Linux Enterprise Workstation Extension 12 x86_64",
      "SUSE Linux Enterprise Software Development Kit 12 x86_64",
      "Advanced Systems Management Module 12 x86_64",
      "Containers Module 12 x86_64",
      "Legacy Module 12 x86_64",
      "Public Cloud Module 12 x86_64",
      "Toolchain Module 12 x86_64",
      "Web and Scripting Module 12 x86_64"
    ]

    expect(available_addons.sort(&Registration::ADDON_SORTER).map(&:label)).to eql(expected)
  end

  it "moves the unknown product types at the end" do
    if RUBY_VERSION.start_with?("3.0.")
      pending "YaML loading of older OpenStruct is broken in ruby 3.0"
    end

    # AdvMgmt and Legacy have undefined type => at the end
    expected = [
      "sle-sdk", "sle-we", "sle-module-public-cloud",
      "sle-module-web-scripting", "sle-module-legacy",
      "sle-module-adv-systems-management"
    ]

    expect(unknown_addons.sort(&Registration::ADDON_SORTER).map(&:identifier)).to eql(expected)
  end
end
