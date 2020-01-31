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
require "registration/dialogs/online_search"
require "cwm/rspec"

describe Registration::Dialogs::OnlineSearch do
  subject(:dialog) { described_class.new }

  describe "#selected_packages" do
    let(:search_widget) do
      Registration::Widgets::PackageSearch.new(controller)
    end

    let(:controller) do
      Registration::Controllers::PackageSearch.new
    end

    let(:package) do
      instance_double(Registration::RemotePackage, name: "gnome-desktop")
    end

    before do
      allow(Registration::Widgets::PackageSearch).to receive(:new)
        .and_return(search_widget)
      allow(Registration::Controllers::PackageSearch).to receive(:new)
        .and_return(controller)
      allow(controller).to receive(:selected_packages).and_return([package])
      allow(subject).to receive(:cwm_show).and_return(result)
    end

    context "when the user aborts the search" do
      let(:result) { :abort }

      it "returns an empty array" do
        subject.run
        expect(subject.selected_packages).to eq([])
      end
    end

    context "when the user selects some packages for installation" do
      let(:result) { :next }

      it "returns the selected packages" do
        subject.run
        expect(subject.selected_packages).to eq([package])
      end
    end
  end
end
