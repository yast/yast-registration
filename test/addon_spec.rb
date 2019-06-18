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
      expect(addons.any? { |addon| addon.children.size == 1 }).to eq(true)
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

      ha = addons.find { |addon| addon.identifier == "sle-ha" }
      ha_geo = ha.children.first

      expect(ha.registered?).to eq(true)
      expect(ha_geo.registered?).to eq(true)
    end
  end

  describe ".selected" do
    it "returns array with selected addons" do
      expect(Registration::Addon.selected).to be_a(Array)
    end
  end

  describe ".accepted" do
    let(:eula_url) { "http://example.eula.url" }
    let(:params) { { "eula_url" => eula_url } }
    let(:wo_eula) { Registration::Addon.new(addon_generator) }
    let(:refused) { Registration::Addon.new(addon_generator(params)) }
    let(:accepted) { Registration::Addon.new(addon_generator(params)) }
    let(:not_selected) { Registration::Addon.new(addon_generator(params)) }
    let(:registration) do
      double(
        get_addon_list: [wo_eula, refused, accepted, not_selected]
      )
    end

    before do
      wo_eula.selected

      refused.selected
      refused.refuse_eula

      accepted.selected
      accepted.accept_eula

      not_selected.accept_eula
    end

    it "returns a collection" do
      expect(described_class.accepted).to be_a(Array)
    end

    it "includes selected addons w/o required EULA" do
      expect(described_class.accepted).to include(wo_eula)
    end

    it "includes selected addons with accepted EULA" do
      expect(described_class.accepted).to include(accepted)
    end

    it "does not includes selected addons with refused EULA" do
      expect(described_class.accepted).to_not include(refused)
    end

    it "does not includes not selected addons" do
      expect(described_class.accepted).to_not include(not_selected)
    end
  end

  describe ".to_register" do
    let(:eula_url) { "http://example.eula.url" }
    let(:params) { { "eula_url" => eula_url } }
    let(:wo_eula) { Registration::Addon.new(addon_generator) }
    let(:refused) { Registration::Addon.new(addon_generator(params)) }
    let(:accepted) { Registration::Addon.new(addon_generator(params)) }
    let(:registered) { Registration::Addon.new(addon_generator(params)) }
    let(:not_selected) { Registration::Addon.new(addon_generator(params)) }
    let(:available_addons) { [wo_eula, refused, accepted, registered, not_selected] }

    let(:registration) { double(
      get_addon_list: available_addons
      )
    }

    before do
      available_addons.each(&:selected)

      refused.refuse_eula
      accepted.accept_eula
      registered.accept_eula
      registered.registered
    end

    it "returns a collection" do
      expect(described_class.accepted).to be_a(Array)
    end

    it "includes selected addons w/o required EULA" do
      expect(described_class.accepted).to include(wo_eula)
    end

    it "includes selected addons with accepted EULA" do
      expect(described_class.accepted).to include(accepted)
    end

    it "does not include selected addons with refused EULA" do
      expect(described_class.to_register).to_not include(refused)
    end

    it "does not includes not selected addons" do
      expect(described_class.accepted).to_not include(not_selected)
    end

    it "does not include already registered addons" do
      expect(described_class.to_register).to_not include(registered)
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
      expect(Yast::Pkg).to receive(:ResolvableProperties).with(prod2.identifier, :product, "")
        .and_return(["status" => :available])
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
      expect(Yast::Pkg).to receive(:ResolvableProperties).with(prod.identifier, :product, "")
        .and_return([])

      expect(Registration::Addon.registered_not_installed).to be_empty
    end
  end

  describe "#accept_eula" do
    it "sets EULA as accepted" do
      addon.accept_eula

      expect(addon.eula_accepted).to eq(true)
    end
  end

  describe "#refuse_eula" do
    it "sets EULA as not accepted" do
      addon.refuse_eula

      expect(addon.eula_accepted).to eq(false)
    end
  end

  describe "#eula_refused?" do
    context "when EULA acceptance is not required" do
      before do
        allow(addon).to receive(:eula_acceptance_needed?).and_return(false)
      end

      it "returns false" do
        expect(addon.eula_refused?).to eq(false)
      end
    end

    context "when EULA acceptance is required" do
      before do
        allow(addon).to receive(:eula_acceptance_needed?).and_return(true)
      end

      context "and the license was accepted" do
        it "returns false" do
          addon.accept_eula

          expect(addon.eula_refused?).to eq(false)
        end
      end

      context "and the license was refused" do
        it "returns true" do
          addon.refuse_eula

          expect(addon.eula_refused?).to eq(true)
        end
      end
    end
  end

  context "#eula_acceptance_needed" do
    let(:eula_url) { nil }

    before do
      allow(addon).to receive(:eula_url).and_return(eula_url)
    end

    context "when there is not an EULA url" do
      it "returns false" do
        expect(addon.eula_acceptance_needed?).to eq(false)
      end
    end

    context "when there is an empty EULA url" do
      let(:eula_url) { "  " }

      it "returns false" do
        expect(addon.eula_acceptance_needed?).to eq(false)
      end
    end

    context "when there is a NOT empty EULA url" do
      let(:eula_url) { "http://example.eula.url" }

      it "returns true" do
        expect(addon.eula_acceptance_needed?).to eq(true)
      end
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

  describe "#beta_release?" do
    it "returns true if addon is beta release" do
      product = addon_generator("release_stage" => "beta")
      addon = Registration::Addon.new(product)

      expect(addon.beta_release?).to eq(true)
    end

    it "returns false if addon is not beta release" do
      product = addon_generator("release_stage" => "production")
      addon = Registration::Addon.new(product)

      expect(addon.beta_release?).to eq(false)
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
    let(:child) { parent.children.first }

    it "returns false when the addon has been already registered" do
      addon.registered
      expect(addon.selectable?).to eq(false)
    end

    it "returns true when the addon has not been already registered" do
      expect(addon.selectable?).to eq(true)
    end

    it "returns false when the parent is not selected or registered" do
      expect(child.selectable?).to eq(false)
    end

    it "returns true when the parent is selected" do
      parent.selected
      expect(child.selectable?).to eq(true)
    end

    it "returns true when the parent is registered" do
      parent.registered
      expect(child.selectable?).to eq(true)
    end

    it "returns false when any child is selected" do
      child.selected
      expect(parent.selectable?).to eq(false)
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
