#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/addon"

describe Registration::Addon do

  describe ".required_addons" do
    it "returns empty list if there are no dependencies" do
      addon = Registration::Addon.new("SUSE_SLES", "12", "x86_64")

      expect(addon.required_addons).to be_empty
    end

    it "returns an array containing the dependency name" do
      addon1 = Registration::Addon.new("SUSE_ADDON1", "12", "x86_64")
      addon2 = Registration::Addon.new("SUSE_ADDON2", "12", "x86_64", depends_on: [addon1])

      expect(addon2.required_addons).to eq([addon1])
    end

    it "removes duplicates" do
      addon1 = Registration::Addon.new("SUSE_ADDON1", "12", "x86_64")
      addon2 = Registration::Addon.new("SUSE_ADDON2", "12", "x86_64", depends_on: [addon1])
      addon3 = Registration::Addon.new("SUSE_ADDON3", "12", "x86_64", depends_on: [addon1])
      addon4 = Registration::Addon.new("SUSE_ADDON3", "12", "x86_64", depends_on: [addon1])
      addon5 = Registration::Addon.new("SUSE_ADDON3", "12", "x86_64", depends_on: [addon2, addon3, addon4])

      required_addons = addon5.required_addons

      expect(required_addons).to eq(required_addons.uniq)
      expect(required_addons).to include(addon1, addon2, addon3, addon4)
    end

    it "returns transitive dependencies" do
      addon1 = Registration::Addon.new("SUSE_ADDON1", "12", "x86_64")
      addon2 = Registration::Addon.new("SUSE_ADDON2", "12", "x86_64", depends_on: [addon1])
      addon3 = Registration::Addon.new("SUSE_ADDON3", "12", "x86_64", depends_on: [addon2])

      expect(addon3.required_addons).to include(addon1, addon2)
    end

    it "returns multiple transitive dependencies" do
      addon1 = Registration::Addon.new("SUSE_ADDON1", "12", "x86_64")
      addon2 = Registration::Addon.new("SUSE_ADDON2", "12", "x86_64")
      addon3 = Registration::Addon.new("SUSE_ADDON3", "12", "x86_64", depends_on: [addon1, addon2])
      addon4 = Registration::Addon.new("SUSE_ADDON4", "12", "x86_64")
      addon5 = Registration::Addon.new("SUSE_ADDON5", "12", "x86_64")
      addon6 = Registration::Addon.new("SUSE_ADDON6", "12", "x86_64", depends_on: [addon4, addon5])
      addon7 = Registration::Addon.new("SUSE_ADDON7", "12", "x86_64", depends_on: [addon3, addon6])

      required_addons = addon7.required_addons
      expect(required_addons.size).to eq(6)
      expect(required_addons).to include(addon1, addon2, addon3, addon4, addon5, addon6)
    end
  end

end

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
