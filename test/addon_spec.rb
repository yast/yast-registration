#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/addon"
require "suse/connect"

describe Registration::Addon do

  before(:each) do
    addon_reset_cache
  end

  def product_generator(attrs = {})
    params = {}
    params['name'] = attrs['name'] || "Product#{rand(100000)}"
    params['long_name'] = attrs['long_name'] || "The best cool #{params['name']}"
    params['description'] = attrs['description'] || "Bla bla bla bla!"
    params['zypper_name'] = attrs['zypper_name'] || "prod#{rand(100000)}"
    params['zypper_version'] = attrs['version'] || "#{rand(13)}"
    params['arch'] = attrs['arch'] || "x86_64"
    params['free'] = attrs.fetch('free', true)
    params['eula_url'] = attrs['eula_url']
    params["extensions"] = attrs['extensions'] || []

    return params
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

  describe ".selecteds" do
    it "returns array with selected addons" do
      expect(Registration::Addon.selecteds).to be_a(Array)
    end
  end

  describe ".registereds" do
    it "returns array of already registered addons" do
      expect(Registration::Addon.registereds).to be_a(Array)
    end
  end

  describe "#selected?" do
    it "returns if addon is selected for installation" do
      expect(addon.selected?).to be_false
      Registration::Addon.selecteds << addon
      expect(addon.selected?).to be_true
    end
  end

  describe "#selected" do
    it "marks addon as selected" do
      expect(Registration::Addon.selecteds.include?(addon)).to be_false
      addon.selected
      expect(Registration::Addon.selecteds.include?(addon)).to be_true
    end

    it "adds to list of selected only one" do
      addon.selected
      addon.selected
      expect(Registration::Addon.selecteds.count(addon)).to be 1
    end
  end

  describe "#unselected" do
    it "marks addon as unselected" do
      Registration::Addon.selecteds << addon
      addon.unselected
      expect(Registration::Addon.selecteds.include?(addon)).to be_false
    end

    it "do nothing if addon is not selected" do
      expect{addon.unselected}.to_not raise_error
    end
  end

  describe "#registered?" do
    it "returns if addon is already registered" do
      expect(addon.registered?).to be_false
      Registration::Addon.registereds << addon
      expect(addon.registered?).to be_true
    end
  end
end
