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

require "cwm/rspec"
require "registration/widgets/addons_selector"

describe Registration::Widgets::AddonsSelector do
  subject(:addons_selector) { described_class.new(addons) }

  include_examples "CWM::CustomWidget"

  let(:addons) { load_yaml_fixture("sle15_addons.yaml") }
  let(:sle_we_addon) { addons.find { |a| a.identifier == "sle-we" } }
  let(:basesystem_module_addon) { addons.find { |a| a.identifier == "sle-module-basesystem" } }

  before do
    addon_reset_cache
    allow(Registration::Addon).to receive(:find_all).and_return(addons)
  end

  describe "#initialize" do
    let(:last_filter_value) { nil }

    before do
      allow(described_class).to receive(:release_only).and_return(last_filter_value)
    end

    context "when filter has not been set yet" do
      it "sets it to default value" do
        expect(described_class).to receive(:release_only=).with(true)

        subject
      end
    end

    context "when filter has been set previously" do
      let(:last_filter_value) { false }

      it "does not set it to the default" do
        expect(described_class).to_not receive(:release_only=)

        subject
      end
    end
  end

  describe "#items" do
    context "when not filtering unreleased addons" do
      before do
        allow(described_class).to receive(:release_only).and_return(false)
      end

      it "includes all addons" do
        expect(subject.items.map(&:label)).to contain_exactly(*addons.map(&:label))
      end
    end

    context "when filtering unreleased addons" do
      let(:released_addons) { addons.select(&:released?) }

      before do
        allow(described_class).to receive(:release_only).and_return(true)
        allow(basesystem_module_addon).to receive(:released?).and_return(true)
      end

      it "does not include unreleased addons" do
        expect(subject.items.map(&:label)).to eq([basesystem_module_addon.label])
      end

      context "but a not released addon is already registered" do
        before do
          allow(sle_we_addon).to receive(:registered?).and_return(true)
        end

        it "includes it too" do
          expect(subject.items.map(&:label)).to include(sle_we_addon.label)
        end
      end

      context "but a not released addon is selected" do
        before do
          allow(sle_we_addon).to receive(:selected?).and_return(true)
        end

        it "includes it too" do
          expect(subject.items.map(&:label)).to include(sle_we_addon.label)
        end
      end
    end
  end
end

describe Registration::Widgets::AddonsSelector::Item do
  subject(:item) { described_class.new(addon) }

  let(:addons) { load_yaml_fixture("sle15_addons.yaml") }
  let(:addon) { addons.find { |a| a.identifier == "sle-module-basesystem" } }

  describe "#id" do
    it "returns a String" do
      expect(subject.id).to be_a(String)
    end

    it "includes the addon identifier" do
      expect(subject.id).to include(addon.identifier)
    end
  end

  describe "#label" do
    it "returns the addon label" do
      expect(subject.label).to eq(addon.label)
    end

    context "when the addon is not available" do
      before do
        allow(addon).to receive(:available?).and_return(false)
      end

      it "includes 'not available'" do
        expect(subject.label).to match(/not available/)
      end
    end
  end

  describe "#visible?" do
    context "when the addon is released" do
      before do
        allow(addon).to receive(:released?).and_return(true)
      end

      it "returns true" do
        expect(subject.visible?).to eq(true)
      end
    end

    context "when the addon is not released" do
      before do
        allow(addon).to receive(:released?).and_return(false)
      end

      it "returns false" do
        expect(subject.visible?).to eq(false)
      end

      context "but the addon is already registered" do
        before do
          allow(addon).to receive(:registered?).and_return(true)
        end

        it "returns true" do
          expect(subject.visible?).to eq(true)
        end
      end

      context "but the addon is already selected" do
        before do
          allow(addon).to receive(:selected?).and_return(true)
        end

        it "returns true" do
          expect(subject.visible?).to eq(true)
        end
      end

      context "but the addon has been auto selected" do
        before do
          allow(addon).to receive(:auto_selected?).and_return(true)
        end

        it "returns true" do
          expect(subject.visible?).to eq(true)
        end
      end
    end
  end

  describe "#status" do
    context "when the addon is selected" do
      before do
        allow(addon).to receive(:status).and_return(:selected)
      end

      it "returns :selected" do
        expect(subject.status).to eq(:selected)
      end
    end

    context "when the addon is registered" do
      before do
        allow(addon).to receive(:status).and_return(:registered)
      end

      it "returns :selected" do
        expect(subject.status).to eq(:selected)
      end
    end

    context "when the addon is not selected" do
      before do
        allow(addon).to receive(:status).and_return(:unselected)
      end

      it "returns :unselected" do
        expect(subject.status).to eq(:unselected)
      end
    end

    context "when the addon status is unknown" do
      before do
        allow(addon).to receive(:status).and_return(:whatever)
      end

      it "returns :unselected" do
        expect(subject.status).to eq(:unselected)
      end
    end

    context "when the addon has been auto selected" do
      before do
        allow(addon).to receive(:status).and_return(:auto_selected)
      end

      it "returns :auto_selected" do
        expect(subject.status).to eq(:auto_selected)
      end
    end
  end

  describe "#toggle" do
    it "requests the addon selection toggle" do
      expect(addon).to receive(:toggle_selected)

      subject.toggle
    end
  end

  describe "#description" do
    it "returns the addon description" do
      expect(subject.description).to eq(addon.description)
    end
  end

  describe "#enabled?" do
    it "returns the addon availability" do
      expect(subject.enabled?).to eq(addon.available?)
    end
  end
end
