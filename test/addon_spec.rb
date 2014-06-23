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
      registration = double(:get_addon_list => [prod1, prod2])

      expect(Registration::Addon.find_all(registration).size).to be 2
    end

    it "find even dependend products" do
      prod1 = addon_with_child_generator
      registration = double(:get_addon_list => [prod1])

      expect(Registration::Addon.find_all(registration).size).to be 2
    end

    it "sets properly dependencies between addons" do
      prod1 = addon_with_child_generator
      registration = double(:get_addon_list => [prod1])

      addons = Registration::Addon.find_all(registration)
      expect(addons.any? {|addon| addon.children.size == 1}).to be_true
      expect(addons.any?(&:depends_on)).to be_true
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
      Registration::Addon.find_all(double(:get_addon_list => [addon_with_child_generator]))
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

end
