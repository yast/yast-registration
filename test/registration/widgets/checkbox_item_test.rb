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

require "registration/widgets/checkbox_item"

describe Registration::Widgets::CheckboxItem do
  subject { described_class.new(item.id, item.label, item.status, item.enabled) }

  let(:item) do
    double(
      "Item",
      id:      "whatever",
      label:   "Text uses as label",
      status:  status,
      enabled: enabled
    )
  end

  let(:status) { :selected }
  let(:enabled) { true }

  describe "#to_s" do
    it "returns a string" do
      expect(subject.to_s).to be_a(String)
    end

    context "when the item is enabled" do
      it "includes a link for the input" do
        expect(subject.to_s).to match(/.*href="whatever#checkbox#input".*/)
      end

      it "includes a link for the label" do
        expect(subject.to_s).to match(/.*href="whatever#checkbox#label".*/)
      end

      it "includes the item label" do
        expect(subject.to_s).to include(item.label)
      end
    end

    context "when the item is not enabled" do
      let(:enabled) { false }

      it "uses a grey color" do
        expect(subject.to_s).to match(/.*color: grey.*/)
      end

      it "includes the item label" do
        expect(subject.to_s).to include(item.label)
      end

      it "does not include a link for the input" do
        expect(subject.to_s).to_not match(/.*href="whatever#checkbox#input".*/)
      end

      it "does not include a link for the label" do
        expect(subject.to_s).to_not match(/.*href="whatever#checkbox#label".*/)
      end
    end

    context "when running in text mode" do
      before { allow(Yast::UI).to receive(:TextMode).and_return(true) }

      context "and the item is selected" do
        let(:status) { :selected }

        it "displays `[x]` as icon" do
          expect(subject.to_s).to include("[x]")
        end
      end

      context "and the item is auto registered" do
        let(:status) { :registered }

        it "displays `[x]` as icon" do
          expect(subject.to_s).to include("[x]")
        end
      end

      context "and the item is auto selected" do
        let(:status) { :auto_selected }

        it "displays `[a]` as icon" do
          expect(subject.to_s).to include("[a]")
        end
      end

      context "and the item is not selected or registered yet" do
        let(:status) { :unknown }

        it "displays `[ ]` as icon" do
          expect(subject.to_s).to include("[ ]")
        end
      end
    end

    context "when NOT running in text mode" do
      before { allow(Yast::UI).to receive(:TextMode).and_return(false) }

      context "and the item is selected" do
        let(:status) { :selected }

        it "displays the proper icon" do
          expect(subject.to_s).to include("checkbox-on.svg")
        end
      end

      context "and the item is auto registered" do
        let(:status) { :registered }

        it "displays the proper icon" do
          expect(subject.to_s).to include("checkbox-on.svg")
        end
      end

      context "and the item is auto selected" do
        let(:status) { :auto_selected }

        it "displays the proper icon" do
          expect(subject.to_s).to include("auto-selected.svg")
        end
      end

      context "and the item is not selected or registered yet" do
        let(:status) { :unknown }

        it "displays the proper icon" do
          expect(subject.to_s).to include("checkbox-off.svg")
        end
      end
    end
  end
end
