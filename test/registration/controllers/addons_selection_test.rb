# Copyright (c) [2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require_relative "../../spec_helper"
require "registration/controllers/addons_selection"

describe Registration::Controllers::AddonsSelection do
  subject(:controller) { described_class.new(registration) }

  let(:addons) { load_yaml_fixture("sle15_addons.yaml") }
  let(:sle_we_addon) { addons.find { |a| a.identifier == "sle-we" } }
  let(:basesystem_module_addon) { addons.find { |a| a.identifier == "sle-module-basesystem" } }

  let(:addons_list) do
    [sle_we_addon, basesystem_module_addon]
  end

  let(:registration) do
    instance_double(
      Registration::Registration,
      activated_products: [], get_addon_list: addons_list
    )
  end

  before do
    addon_reset_cache
    allow(Registration::Addon).to receive(:find_all).and_return(addons)
  end

  describe "#initialize" do
    let(:last_filter_value) { nil }

    before do
      allow(described_class).to receive(:filtering_unreleased).and_return(last_filter_value)
    end

    context "when filter has not been set yet" do
      it "sets it to default value" do
        expect(described_class).to receive(:filtering_unreleased=).with(true)

        subject
      end
    end

    context "when filter has been set previously" do
      let(:last_filter_value) { false }

      it "does not set it to the default" do
        expect(described_class).to_not receive(:filtering_unreleased=)

        subject
      end
    end

    context "if there are recommended addons" do
      context "and there are neither, selected nor registered addons yet" do
        it "preselects the recommended addons" do
          subject

          expect(basesystem_module_addon).to be_selected
        end
      end

      context "but there is already an addon selected" do
        before do
          allow(Registration::Addon).to receive(:selected).and_return([sle_we_addon])
        end

        it "does not preselect the recommended addons" do
          subject

          expect(basesystem_module_addon).to_not be_selected
        end
      end

      context "but there is already an addon registered" do
        before do
          allow(Registration::Addon).to receive(:registered).and_return([sle_we_addon])
        end

        it "does not preselect the recommended addons" do
          subject

          expect(basesystem_module_addon).to_not be_selected
        end
      end
    end
  end

  describe "#items" do
    let(:unreleased_addons) { addons.select(&:released?) }

    context "when not filtering unreleased addons" do
      before do
        allow(basesystem_module_addon).to receive(:released?).and_return(true)
        allow(described_class).to receive(:filtering_unreleased).and_return(false)
      end

      it "includes unreleased addons" do
        expect(subject.items.map(&:label)).to contain_exactly(*addons.map(&:label))
      end
    end

    context "when filtering unreleased addons" do
      before do
        allow(described_class).to receive(:filtering_unreleased).and_return(true)
      end

      it "does not include unreleased addons" do
        expect(subject.items.map(&:label)).to eq([basesystem_module_addon.label])
      end
    end
  end

  describe "#find_item" do
    let(:item) { subject.items.first }

    context "when requested item exists" do
      it "returns its item representation" do
        expect(subject.find_item(item.id)).to be_an(described_class::Item)
      end
    end

    context "when requested item does not exist" do
      it "returns nil" do
        expect(subject.find_item("wrong_id")).to be_nil
      end
    end
  end

  describe "#toggle_item_selection" do
    let(:addon) { basesystem_module_addon }
    let(:item) { subject.items.find { |i| i.id.include?(addon.identifier) } }

    it "requests an addon selection change" do
      expect(addon).to receive(:toggle_selected)

      subject.toggle_item_selection(item)
    end
  end

  describe "#selected_items" do
    let(:selected_addons) { addons_list }

    before do
      allow(Registration::Addon).to receive(:selected).and_return(selected_addons)
    end

    it "logs selected addons" do
      expect(subject.log).to receive(:info).with(/Selected addons:/)

      subject.selected_items
    end

    it "returns selected addons" do
      expect(subject.selected_items).to eq(selected_addons)
    end
  end

  describe "#restore_selection" do
    let(:initial_selection) { [sle_we_addon] }
    let(:new_selection) { addons_list }

    before do
      allow(Registration::Addon).to receive(:selected).and_return(initial_selection, new_selection)
    end

    it "undoes the current selection by restoring the initial one" do
      expect(subject.selected_items).to eq(new_selection)

      subject.restore_selection

      expect(Registration::Addon.selected).to eq(initial_selection)
    end
  end

  describe "#detail_options" do
    it "returns a hash" do
      expect(subject.detail_options).to be_a(Hash)
    end

    it "includes the placeholder" do
      expect(subject.detail_options).to include(:placeholder)
    end
  end

  describe "#master_options" do
    it "returns a hash" do
      expect(subject.master_options).to be_a(Hash)
    end
  end

  describe "#include_filter?" do
    let(:addons_list) do
      [sle_we_addon, basesystem_module_addon]
    end

    let(:sle_we_released) { true }
    let(:basesystem_released) { false }

    before do
      allow(Registration::Addon).to receive(:find_all).and_return(addons_list)
      allow(sle_we_addon).to receive(:released?).and_return(sle_we_released)
      allow(basesystem_module_addon).to receive(:released?).and_return(basesystem_released)
    end

    context "when there are development addons available" do
      context "but all of them are already registered" do
        before do
          basesystem_module_addon.registered
        end

        it "returns false" do
          expect(subject.include_filter?).to eq(false)
        end
      end

      context "and any of them is not registered yet" do
        it "returns true" do
          expect(subject.include_filter?).to eq(true)
        end
      end
    end

    context "when there are not development addons available" do
      let(:sle_we_released) { true }
      let(:basesystem_released) { true }

      it "returns false" do
        expect(subject.include_filter?).to eq(false)
      end
    end
  end

  describe "#filter_label" do
    it "returns an string" do
      expect(subject.filter_label).to be_a(String)
    end
  end

  describe "#filter=" do
    it "updates the filtering_unreleased class flag with given value" do
      expect(described_class).to receive(:filtering_unreleased=).with(true)
      subject.filter = true

      expect(described_class).to receive(:filtering_unreleased=).with(false)
      subject.filter = false
    end
  end
end
