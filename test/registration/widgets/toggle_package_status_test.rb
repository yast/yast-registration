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
require "registration/widgets/toggle_package_status"

describe Registration::Widgets::TogglePackageStatus do
  include Yast::UIShortcuts

  include_examples "CWM::PushButton"

  let(:id) { Id(subject.widget_id) }

  let(:installed) { false }
  let(:selected) { false }

  let(:package) do
    instance_double(
      Registration::RemotePackage,
      name: "yast2", full_version: "4.2.49-1.1", arch: "x86_64",
      installed?: installed, selected?: selected
    )
  end

  describe "#refresh" do
    before do
      allow(Yast::UI).to receive(:ChangeWidget)
    end

    it "recalculates the layout" do
      # Ensures that the label is always visible,
      # even after changing from a short label to longer one
      expect(Yast::UI).to receive(:RecalcLayout)

      subject.update(package)
    end

    context "when a package is not given" do
      it "uses 'Select' as label" do
        expect(Yast::UI).to receive(:ChangeWidget).with(id, :Label, "Select package")

        subject.update(nil)
      end

      it "sets as disabled" do
        expect(Yast::UI).to receive(:ChangeWidget).with(id, :Enabled, false)

        subject.update(nil)
      end
    end

    context "when a package is given" do
      context "and it's installed" do
        let(:installed) { true }

        it "uses 'Installed' as label" do
          expect(Yast::UI).to receive(:ChangeWidget).with(id, :Label, "Already installed")

          subject.update(package)
        end

        it "sets as disabled" do
          expect(Yast::UI).to receive(:ChangeWidget).with(id, :Enabled, false)

          subject.update(package)
        end
      end

      context "and it's selected" do
        let(:selected) { true }

        it "uses 'Unselect' as label" do
          expect(Yast::UI).to receive(:ChangeWidget).with(id, :Label, "Unselect package")

          subject.update(package)
        end

        it "sets as enabled" do
          expect(Yast::UI).to receive(:ChangeWidget).with(id, :Enabled, true)

          subject.update(package)
        end
      end

      context "and it's unselected" do
        it "uses 'Select' as label" do
          expect(Yast::UI).to receive(:ChangeWidget).with(id, :Label, "Select package")

          subject.update(package)
        end

        it "sets as enabled" do
          expect(Yast::UI).to receive(:ChangeWidget).with(id, :Enabled, true)

          subject.update(package)
        end
      end
    end
  end
end
