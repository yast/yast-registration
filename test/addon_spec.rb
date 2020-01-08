#! /usr/bin/env rspec

require_relative "spec_helper"
require "yaml"

describe Registration::Addon do
  before(:each) do
    addon_reset_cache
  end

  subject(:addon) do
    Registration::Addon.new(addon_generator)
  end

  describe ".find_all" do
    it "find all addons for current base product" do
      prod1 = addon_generator
      prod2 = addon_generator
      registration = double(
        activated_products: [],
        get_addon_list:     [prod1, prod2]
      )

      expect(Registration::Addon.find_all(registration).size).to be 2
    end

    it "find even dependend products" do
      prod1 = addon_with_child_generator
      registration = double(
        activated_products: [],
        get_addon_list:     [prod1]
      )

      expect(Registration::Addon.find_all(registration).size).to be 2
    end

    it "sets properly dependencies between addons" do
      prod1 = addon_with_child_generator
      registration = double(
        activated_products: [],
        get_addon_list:     [prod1]
      )

      addons = Registration::Addon.find_all(registration)
      expect(addons.any?(&:depends_on)).to eq(true)
    end

    it "sets the registration status from status call" do
      prod1 = addon_generator("name" => "prod1")
      prod2 = addon_generator("name" => "prod2")
      registration = double(
        activated_products: [prod1],
        get_addon_list:     [prod1, prod2]
      )

      addons = Registration::Addon.find_all(registration)

      addon1 = addons.find { |addon| addon.name == "prod1" }
      addon2 = addons.find { |addon| addon.name == "prod2" }

      expect(addon1.registered?).to eq(true)
      expect(addon2.registered?).to eq(false)
    end

    it "sets the registration status for dependent addons" do
      registration = double(
        activated_products: load_yaml_fixture("activated_products.yml"),
        get_addon_list:     load_yaml_fixture("pure_addons.yml")
      )

      addons = Registration::Addon.find_all(registration)

      ha_geo = addons.find { |addon| addon.identifier == "sle-ha-geo" }
      ha = ha_geo.depends_on

      expect(ha.registered?).to eq(true)
      expect(ha_geo.registered?).to eq(true)
    end
  end

  describe "#find_by_id" do
    before do
      registration = double(
        activated_products: [],
        get_addon_list:     load_yaml_fixture("pure_addons.yml")
      )
      Registration::Addon.find_all(registration)
    end

    it "returns the addon witht the given ID" do
      addon = described_class.find_by_id(1222)
      expect(addon.identifier).to eq("sle-we")
    end

    it "returns nil if the addon does not exist" do
      expect(described_class.find_by_id(1)).to be_nil
    end

    context "when no addons were read" do
      before do
        described_class.reset!
      end

      it "raises an exception" do
        expect { described_class.find_by_id(1) }
          .to raise_error(Registration::Addon::AddonsNotLoaded)
      end
    end
  end

  describe ".registration_order" do
    it "returns addons sorted in the registration order" do
      addons = load_yaml_fixture("sle15_addons.yaml")
      sorted_addons = Registration::Addon.registration_order(addons)
      expected_output = [
        "sle-module-basesystem", "sle-module-desktop-applications",
        "sle-module-legacy", "sle-module-public-cloud", "sle-ha",
        "sle-module-development-tools", "sle-module-server-applications", "sle-we"
      ]

      expect(addons.size).to eq sorted_addons.size
      expect(sorted_addons.map(&:identifier)).to eq expected_output
    end
  end

  describe ".selected" do
    it "returns array with selected addons" do
      expect(Registration::Addon.selected).to be_a(Array)
    end
  end

  describe ".registered" do
    it "returns array of already registered addons" do
      expect(Registration::Addon.registered).to be_a(Array)
    end
  end

  describe ".registered_not_installed" do
    it "returns an array of already registered addons but not installed" do
      prod1 = addon_generator("name" => "prod1")
      prod2 = addon_generator("name" => "prod2")
      registration = double(
        activated_products: [prod2],
        get_addon_list:     [prod1, prod2]
      )

      addons = Registration::Addon.find_all(registration)

      addon2 = addons.find { |addon| addon.name == "prod2" }

      expect(Registration::SwMgmt).to receive(:installed_products).and_return([])
      expect(Y2Packager::Resolvable).to receive(:any?).with(kind: :product,
        name: prod2.identifier, status: :available)
        .and_return(true)
      reg_not_installed_addons = Registration::Addon.registered_not_installed

      expect(reg_not_installed_addons.size).to eql(1)
      expect(reg_not_installed_addons.first.name).to eql(addon2.name)
    end

    it "does not return addons without available products" do
      prod = addon_generator("name" => "prod")
      registration = double(
        activated_products: [prod],
        get_addon_list:     [prod]
      )

      Registration::Addon.find_all(registration)

      expect(Registration::SwMgmt).to receive(:installed_products).and_return([])
      expect(Y2Packager::Resolvable).to receive(:any?).with(kind: :product,
        name: prod.identifier, status: :available)
        .and_return(false)

      expect(Registration::Addon.registered_not_installed).to be_empty
    end
  end

  describe "#unregistered" do
    it "marks addon as unregistered" do
      Registration::Addon.registered << addon
      addon.unregistered
      expect(Registration::Addon.registered).to_not include(addon)
    end

    it "do nothing if addon is not registered" do
      expect(Registration::Addon.registered).to_not include(addon)
      expect { addon.unregistered }.to_not raise_error
    end
  end

  describe "#selected?" do
    it "returns if addon is selected for installation" do
      expect(addon.selected?).to eq(false)
      Registration::Addon.selected << addon
      expect(addon.selected?).to eq(true)
    end
  end

  describe "#selected" do
    it "marks addon as selected" do
      expect(Registration::Addon.selected.include?(addon)).to eq(false)
      addon.selected
      expect(Registration::Addon.selected.include?(addon)).to eq(true)
    end

    it "adds to list of selected only one" do
      addon.selected
      addon.selected
      expect(Registration::Addon.selected.count(addon)).to be 1
    end
  end

  describe "#unselected" do
    it "marks addon as unselected" do
      Registration::Addon.selected << addon
      addon.unselected
      expect(Registration::Addon.selected.include?(addon)).to eq(false)
    end

    it "do nothing if addon is not selected" do
      expect { addon.unselected }.to_not raise_error
    end
  end

  describe "#toggle_selected" do
    it "marks an unselected addon as selected" do
      expect(Registration::Addon.selected.include?(addon)).to eq(false)
      addon.toggle_selected
      expect(Registration::Addon.selected.include?(addon)).to eq(true)
    end

    it "marks a selected addon as unselected" do
      Registration::Addon.selected << addon
      expect(Registration::Addon.selected.include?(addon)).to eq(true)
      addon.toggle_selected
      expect(Registration::Addon.selected.include?(addon)).to eq(false)
    end
  end

  describe "#registered?" do
    it "returns if addon is already registered" do
      expect(addon.registered?).to eq(false)
      Registration::Addon.registered << addon
      expect(addon.registered?).to eq(true)
    end
  end

  describe "#released?" do
    it "returns false if addon is a testing release" do
      alpha_product = addon_generator("release_stage" => "alpha")
      alpha_addon = Registration::Addon.new(alpha_product)
      beta_product = addon_generator("release_stage" => "beta")
      beta_addon = Registration::Addon.new(beta_product)

      expect(alpha_addon.released?).to eq(false)
      expect(beta_addon.released?).to eq(false)
    end

    it "returns true if addon is a supported release" do
      product = addon_generator("release_stage" => "released")
      addon = Registration::Addon.new(product)

      expect(addon.released?).to eq(true)
    end
  end

  describe "#label" do
    it "returns short name when the long name is nil" do
      product = addon_generator
      product.friendly_name = nil

      addon = Registration::Addon.new(product)
      expect(addon.label).to eq(addon.name)
    end

    it "returns short name when the long name is empty" do
      product = addon_generator("friendly_name" => "")

      addon = Registration::Addon.new(product)
      expect(addon.label).to eq(addon.name)
    end

    it "returns long name if it is present" do
      expect(addon.label).to eq(addon.friendly_name)
    end
  end

  describe "#selectable?" do
    let(:addons) do
      Registration::Addon.find_all(
        double(
          get_addon_list:     [addon_with_child_generator],
          activated_products: []
        )
      )
    end

    let(:parent) { addons.first }
    let(:child) { addons[1] }

    it "returns false when the addon has been already registered" do
      addon.registered
      expect(addon.selectable?).to eq(false)
    end

    it "returns true when the addon has not been already registered" do
      expect(addon.selectable?).to eq(true)
    end

    it "returns true when the parent is selected" do
      parent.selected
      expect(child.selectable?).to eq(true)
    end

    it "returns true when the parent is registered" do
      parent.registered
      expect(child.selectable?).to eq(true)
    end

    it "returns false when the addon is not available" do
      product = addon_generator("available" => false)
      addon = Registration::Addon.new(product)
      expect(addon.selectable?).to eq(false)
    end

    it "returns true when the addon is available" do
      product = addon_generator("available" => true)
      addon = Registration::Addon.new(product)
      expect(addon.selectable?).to eq(true)
    end

    it "returns true when the addon availability is not set" do
      expect(addon.selectable?).to eq(true)
    end
  end

  describe "#updates_addon?" do
    it "returns true if the old addon has the same name" do
      product = addon_generator("zypper_name" => "sle-sdk")

      new_addon = Registration::Addon.new(product)
      old_addon = { "name" => "sle-sdk", "version" => "12", "arch" => "x86_64" }

      expect(new_addon.updates_addon?(old_addon)).to eq(true)
    end

    it "returns true if the old addon is a predecessor" do
      # "sle-haegeo" (SLE11-SP2) has been renamed to "sle-ha-geo" (SLE12)
      product = addon_generator("zypper_name"       => "sle-ha-geo",
                                "former_identifier" => "sle-haegeo")

      new_addon = Registration::Addon.new(product)
      old_addon = { "name" => "sle-haegeo", "version" => "12", "arch" => "x86_64" }

      expect(new_addon.updates_addon?(old_addon)).to eq(true)
    end

    it "returns false if the old addon is different" do
      product = addon_generator("zypper_name" => "sle-sdk")

      new_addon = Registration::Addon.new(product)
      old_addon = { "name" => "sle-hae", "version" => "12", "arch" => "x86_64" }

      expect(new_addon.updates_addon?(old_addon)).to eq(false)
    end
  end

  describe "#to_h" do
    it "returns a Hash representation" do
      product = addon_generator

      addon = Registration::Addon.new(product)
      expect(addon.to_h).to be_a(Hash)
    end
  end
end
