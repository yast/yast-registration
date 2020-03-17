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

require_relative "../spec_helper"
require "registration/remote_package"
require "registration/addon"

describe Registration::RemotePackage do
  subject(:package) do
    described_class.new(
      id: 1, name: "foobar", arch: :x86_64, version: "1.0",
      release: "1", addon: nil, status: :available
    )
  end

  describe "#full_version" do
    it "returns a version including the version number and the release" do
      expect(package.full_version).to eq("1.0-1")
    end
  end

  describe "#select!" do
    it "sets the package as selected" do
      expect { package.select! }.to change { package.selected? }.from(false).to(true)
    end
  end

  describe "#unselect!" do
    context "when the package was selected" do
      before do
        package.select!
      end

      it "reverts the package to the previous status" do
        expect { package.unselect! }.to change { package.status }.from(:selected).to(:available)
      end
    end

    context "when the package is not selected" do
      it "does not modify the status" do
        expect { package.unselect! }.to_not change { package.status }
      end
    end
  end
end
