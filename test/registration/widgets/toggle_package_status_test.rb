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

  subject { described_class.new(package) }

  include_examples "CWM::PushButton"

  let(:installed) { false }
  let(:selected) { false }

  let(:package) do
    instance_double(
      Registration::RemotePackage,
      name: "yast2", full_version: "4.2.49-1.1", arch: "x86_64",
      installed?: installed, selected?: selected
    )
  end

  describe "#label" do
    context "when a package is not given" do
      let(:package) { nil }

      it "uses 'Select package' as label" do
        expect(subject.label).to eq("Select package")
      end
    end

    context "when a package is given" do
      context "and it's installed" do
        let(:installed) { true }

        it "uses 'Already installed' as label" do
          expect(subject.label).to eq("Already installed")
        end
      end

      context "and it's selected" do
        let(:selected) { true }

        it "uses 'Unselect package' as label" do
          expect(subject.label).to eq("Unselect package")
        end
      end

      context "and it's unselected" do
        it "uses 'Select' as label" do
          expect(subject.label).to eq("Select package")
        end
      end
    end
  end

  describe "#opt" do
    context "when a package is not given" do
      let(:package) { nil }

      it "includes :disabled" do
        expect(subject.opt).to include(:disabled)
      end
    end

    context "when a package is already installed" do
      let(:installed) { true }

      it "includes :disabled" do
        expect(subject.opt).to include(:disabled)
      end
    end

    context "when a package is not already installed" do
      it "does not include :disabled" do
        expect(subject.opt).to_not include(:disabled)
      end
    end
  end
end
