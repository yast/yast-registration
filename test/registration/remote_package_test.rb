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
      name: "foobar", arch: :x86_64, version: "1.0", release: "1", addon: nil
    )
  end

  describe "#status" do
    let(:libzypp_package) { instance_double(Y2Packager::Package, status: :available) }

    before do
      allow(package).to receive(:libzypp_package).and_return(libzypp_package)
    end

    it "returns the libzypp counterpart status" do
      expect(package.status).to eq(:available)
    end

    context "when there is no libzypp counterpart" do
      let(:libzypp_package) { nil }

      it "returns :unknown" do
        expect(package.status).to eq(:unknown)
      end
    end
  end
end
