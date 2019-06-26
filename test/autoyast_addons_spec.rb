#! /usr/bin/env rspec
# typed: false

require_relative "spec_helper"
require "yaml"

describe Registration::AutoyastAddons do
  let(:registration) { double("registration") }
  let(:unsorted_addons) do
    [
      # deliberately in a wrong registration order, the "sle-module-basesystem"
      # module needs to be registered first
      { "name" => "sle-module-desktop-applications", "version" => "15", "arch" => "x86_64" },
      { "name" => "sle-module-basesystem", "version" => "15", "arch" => "x86_64" }
    ]
  end

  # it depends on the "sle-module-basesystem" which is not listed here
  let(:incomplete_addons) do
    ["name" => "sle-module-desktop-applications", "version" => "15",
    "arch" => "x86_64"]
  end

  # the basesystem module does not need a reg. key in reality
  # but let's use it in this test for the simplicity
  let(:addons_with_reg_key) do
    ["name" => "sle-module-basesystem", "version" => "15", "arch" => "x86_64",
      "reg_code" => "abcd42"]
  end

  # some dummy non-existing addon to test error handling
  let(:missing_addons) do
    ["name" => "non-existing-module", "version" => "42", "arch" => "x86_64"]
  end

  # the addons to register in the expcted correct order
  let(:expected_registration_order) { ["sle-module-basesystem", "sle-module-desktop-applications"] }

  before do
    addons = load_yaml_fixture("sle15_addons.yaml")
    allow(Registration::Addon).to receive(:find_all).and_return(addons)
    allow(registration).to receive(:get_addon_list).and_return(addons)
  end

  after do
    Registration::Addon.reset!
  end

  describe "#select" do
    it "sorts the addons according to their dependencies" do
      ayaddons = Registration::AutoyastAddons.new(unsorted_addons, registration)
      ayaddons.select

      expect(ayaddons.selected_addons.map(&:identifier)).to eq(expected_registration_order)
    end

    it "automatically selects the dependent addons" do
      ayaddons = Registration::AutoyastAddons.new(incomplete_addons, registration)
      ayaddons.select

      expect(ayaddons.selected_addons.map(&:identifier)).to eq(expected_registration_order)
    end

    it "reports error for not available addons" do
      expect(Yast::Report).to receive(:Error).with(/is not available for registration/)

      ayaddons = Registration::AutoyastAddons.new(missing_addons, registration)
      ayaddons.select
    end
  end

  describe "#register" do
    it "registers the selected addons" do
      expect(registration).to receive(:register_product).with(
        "name" => "sle-module-basesystem", "reg_code" => nil, "arch" => "x86_64",
        "version" => "15"
      ).ordered
      expect(registration).to receive(:register_product).with(
        "name" => "sle-module-desktop-applications", "reg_code" => nil,
        "arch" => "x86_64", "version" => "15"
      ).ordered

      ayaddons = Registration::AutoyastAddons.new(unsorted_addons, registration)
      ayaddons.select
      ayaddons.register
    end

    it "registers the selected addon using the provided reg. key" do
      expect(registration).to receive(:register_product).with(
        "name" => "sle-module-basesystem", "reg_code" => "abcd42", "arch" => "x86_64",
        "version" => "15"
      )

      ayaddons = Registration::AutoyastAddons.new(addons_with_reg_key, registration)
      ayaddons.select
      ayaddons.register
    end
  end

end
