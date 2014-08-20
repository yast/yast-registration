#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/addon"
require "suse/connect"

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
        :activated_products => [],
        :get_addon_list => [prod1, prod2]
      )

      expect(Registration::Addon.find_all(registration).size).to be 2
    end

    it "find even dependend products" do
      prod1 = addon_with_child_generator
      registration = double(
        :activated_products => [],
        :get_addon_list => [prod1]
      )

      expect(Registration::Addon.find_all(registration).size).to be 2
    end

    it "sets properly dependencies between addons" do
      prod1 = addon_with_child_generator
      registration = double(
        :activated_products => [],
        :get_addon_list => [prod1]
      )

      addons = Registration::Addon.find_all(registration)
      expect(addons.any? {|addon| addon.children.size == 1}).to be_true
      expect(addons.any?(&:depends_on)).to be_true
    end

    it "sets the registration status from status call" do
      prod1 = addon_generator("name" => "prod1")
      prod2 = addon_generator("name" => "prod2")
      registration = double(
        :activated_products => [prod1],
        :get_addon_list => [prod1, prod2]
      )

      addons = Registration::Addon.find_all(registration)

      addon1 = addons.find{ |addon| addon.name == "prod1"}
      addon2 = addons.find{ |addon| addon.name == "prod2"}

      expect(addon1.registered?).to be_true
      expect(addon2.registered?).to be_false
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

  describe "#unregistered" do
    it "marks addon as unregistered" do
      Registration::Addon.registered << addon
      addon.unregistered
      expect(Registration::Addon.registered).to_not include(addon)
    end

    it "do nothing if addon is not registered" do
      expect(Registration::Addon.registered).to_not include(addon)
      expect{addon.unregistered}.to_not raise_error
    end
  end


  describe "#selected?" do
    it "returns if addon is selected for installation" do
      expect(addon.selected?).to be_false
      Registration::Addon.selected << addon
      expect(addon.selected?).to be_true
    end
  end

  describe "#selected" do
    it "marks addon as selected" do
      expect(Registration::Addon.selected.include?(addon)).to be_false
      addon.selected
      expect(Registration::Addon.selected.include?(addon)).to be_true
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
      expect(Registration::Addon.selected.include?(addon)).to be_false
    end

    it "do nothing if addon is not selected" do
      expect{addon.unselected}.to_not raise_error
    end
  end

  describe "#registered?" do
    it "returns if addon is already registered" do
      expect(addon.registered?).to be_false
      Registration::Addon.registered << addon
      expect(addon.registered?).to be_true
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
      Registration::Addon.find_all(double(
          :get_addon_list => [addon_with_child_generator],
          :activated_products => []
        ))
    end

    let(:parent) { addons.first }
    let(:child) { parent.children.first }

    it "returns false when the addon has been already registered" do
      addon.registered
      expect(addon.selectable?).to be_false
    end

    it "returns true when the addon has not been already registered" do
      expect(addon.selectable?).to be_true
    end

    it "returns false when the parent is not selected or registered" do
      expect(child.selectable?).to be_false
    end

    it "returns true when the parent is selected" do
      parent.selected
      expect(child.selectable?).to be_true
    end

    it "returns true when the parent is registered" do
      parent.registered
      expect(child.selectable?).to be_true
    end

    it "returns false when any child is selected" do
      child.selected
      expect(parent.selectable?).to be_false
    end

    it "returns false when the addon is not available" do
      product = addon_generator("available" => false)
      addon = Registration::Addon.new(product)
      expect(addon.selectable?).to be_false
    end

    it "returns true when the addon is available" do
      product = addon_generator("available" => true)
      addon = Registration::Addon.new(product)
      expect(addon.selectable?).to be_true
    end

    it "returns true when the addon availability is not set" do
      expect(addon.selectable?).to be_true
    end
  end

  describe "#updates_addon?" do
    it "returns true if the old addon has the same name" do
      product = addon_generator("zypper_name" => "sle-sdk")

      new_addon = Registration::Addon.new(product)
      old_addon = { "name" => "sle-sdk", "version" => "12", "arch" => "x86_64" }

      expect(new_addon.updates_addon?(old_addon)).to be_true
    end

    it "returns true if the old addon is a predecessor" do
      # "sle-haegeo" (SLE11-SP2) has been renamed to "sle-ha-geo" (SLE12)
      product = addon_generator("zypper_name" => "sle-ha-geo",
        "former_identifier" => "sle-haegeo")

      new_addon = Registration::Addon.new(product)
      old_addon = { "name" => "sle-haegeo", "version" => "12", "arch" => "x86_64" }

      expect(new_addon.updates_addon?(old_addon)).to be_true
    end

    it "returns false if the old addon is different" do
      product = addon_generator("zypper_name" => "sle-sdk")

      new_addon = Registration::Addon.new(product)
      old_addon = { "name" => "sle-hae", "version" => "12", "arch" => "x86_64" }

      expect(new_addon.updates_addon?(old_addon)).to be_false
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
