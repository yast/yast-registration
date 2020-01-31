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
require "registration/controllers/package_search"

describe Registration::Controllers::PackageSearch do
  subject(:controller) { described_class.new }

  let(:package) do
    instance_double(
      Registration::RemotePackage, id: 1, name: "gnome-desktop", addon: addon,
      selected?: false, select!: nil, installed?: installed?
    )
  end

  let(:addon) do
    instance_double(
      Registration::Addon, name: "desktop", registered?: false, selected?: false,
      auto_selected?: nil, selected: nil, unselected: nil, dependencies: []
    )
  end

  let(:search) do
    instance_double(Registration::PackageSearch, packages: [package])
  end

  let(:installed?) { false }

  let(:text) { "gnome" }

  before do
    allow(Registration::PackageSearch).to receive(:new)
      .with(text: text).and_return(search)
  end

  describe "#search" do
    it "updates the list of packages with results from SCC" do
      expect { controller.search(text) }.to change { controller.packages }
        .from([]).to([package])
    end
  end

  describe "#packages" do
    context "when no search has been peformed" do
      it "returns an empty array" do
        expect(controller.packages).to eq([])
      end
    end

    context "when there are search results" do
      before do
        allow(Registration::PackageSearch).to receive(:new)
          .and_return(search)
        controller.search(text)
      end

      it "returns the search results" do
        expect(controller.packages).to eq([package])
      end
    end
  end
end
