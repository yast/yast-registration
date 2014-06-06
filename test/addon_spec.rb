#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/addon"
require "suse/connect"

describe Registration::Addon do

  # add cache reset, which is not needed in common case
  class Registration::Addon
    class << self
      def reset_cache
        @cached_addons = nil
        @registereds = nil
        @selecteds = nil
      end
    end
  end

  before(:each) do
    Registration::Addon.reset_cache
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
    Registration::Addon.new(SUSE::Connect::Product.new(product_generator))
  end

  describe ".find_all" do
    it "find all addons for current base product" do
      prod1 = SUSE::Connect::Product.new(product_generator)
      prod2 = SUSE::Connect::Product.new(product_generator)
      registration = double(:get_addon_list => [prod1, prod2])

      expect(Registration::Addon.find_all(registration).size).to be 2
    end

    it "find even dependend products" do
      prod_child = product_generator
      prod1 = SUSE::Connect::Product.new(product_generator('extensions' => [prod_child]))
      registration = double(:get_addon_list => [prod1])

      expect(Registration::Addon.find_all(registration).size).to be 2
    end

    it "sets properly dependencies between addons" do
      prod_child = product_generator
      prod1 = SUSE::Connect::Product.new(product_generator('extensions' => [prod_child]))
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
    it "checks if addon is selected" do
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
end

=begin
describe Registration::AddonSorter do
  describe ".registration_order" do
    it "returns registration order according to the dependencies" do
      addon1 = Registration::Addon.new("SUSE_ADDON1", "12", "x86_64")
      addon2 = Registration::Addon.new("SUSE_ADDON2", "12", "x86_64")
      addon3 = Registration::Addon.new("SUSE_ADDON3", "12", "x86_64", depends_on: [addon1, addon2])
      addon4 = Registration::Addon.new("SUSE_ADDON4", "12", "x86_64")
      addon5 = Registration::Addon.new("SUSE_ADDON5", "12", "x86_64")
      addon6 = Registration::Addon.new("SUSE_ADDON6", "12", "x86_64", depends_on: [addon4, addon5])
      addon7 = Registration::Addon.new("SUSE_ADDON7", "12", "x86_64", depends_on: [addon3, addon6])

      # deliberately use an order which does not follow dependencies to make sure it is changed
      addons = [addon7, addon2, addon3, addon5, addon4, addon6, addon1]

      solved = Registration::AddonSorter.registration_order(addons)

      # check the order, iterate over the list and check for missing dependencies
      registered = []
      solved.each do |a|
        # check that all dependendent add-ons are already registered
        expect(a.depends_on - registered).to be_empty
        registered << a
      end
    end

    it "raises KeyError exception when there is an unresolved dependency" do
      addon1 = Registration::Addon.new("SUSE_ADDON1", "12", "x86_64")
      addon2 = Registration::Addon.new("SUSE_ADDON3", "12", "x86_64", depends_on: [addon1])

      expect{Registration::AddonSorter.registration_order([addon2])}.to raise_error(KeyError)
    end
  end
end
=end
