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
require "registration/widgets/package_search"

require "cwm/rspec"

describe Registration::Widgets::PackageSearch do
  include_examples "CWM::CustomWidget"

  subject { described_class.new(controller) }

  let(:controller) do
    Registration::Controllers::PackageSearch.new
  end

  let(:packages_table) do
    instance_double(
      Registration::Widgets::RemotePackagesTable, value: package.id,
      change_items: nil, update_item: nil
    )
  end

  let(:package_details) do
    instance_double(Registration::Widgets::RemotePackageDetails, update: nil, clear: nil)
  end

  let(:package) do
    instance_double(
      Registration::RemotePackage, id: 1, name: "gnome-desktop", addon: addon,
      selected?: false, select!: nil, installed?: installed?
    )
  end

  let(:installed?) { false }

  let(:addon) do
    instance_double(
      Registration::Addon, name: "desktop", registered?: false, selected?: false,
      auto_selected?: nil, selected: nil, unselected: nil, dependencies: []
    )
  end

  let(:search_result) { [package] }

  before do
    allow(Registration::Widgets::RemotePackagesTable).to receive(:new)
      .and_return(packages_table)
    allow(Registration::Widgets::RemotePackageDetails).to receive(:new)
      .and_return(package_details)
    allow(controller).to receive(:search).and_return(search_result)
  end

  describe "#handle" do
    let(:text) { "gnome" }
    let(:ignore_case) { true }

    context "when handling a package search" do
      let(:event) { { "WidgetID" => "search_form_button" } }

      let(:search_form) do
        instance_double(
          Registration::Widgets::PackageSearchForm, text: text, ignore_case: ignore_case
        )
      end

      before do
        allow(Registration::Widgets::PackageSearchForm).to receive(:new)
          .and_return(search_form)
      end

      it "searches for the package in SCC" do
        expect(controller).to receive(:search).with(text, ignore_case)
        subject.handle(event)
      end

      context "but the search text is not enough" do
        let(:text) { "g" }

        it "asks the user to introduce some text" do
          expect(Yast2::Popup).to receive(:show)
            .with(/at least/)
          subject.handle(event)
        end
      end

      context "and there are results" do
        it "updates the table and the package details" do
          expect(packages_table).to receive(:change_items).with([package])
          expect(package_details).to receive(:update).with(package)
          subject.handle(event)
        end
      end

      context "but there are no results" do
        let(:search_result) { [] }

        it "updates the table" do
          expect(packages_table).to receive(:change_items).with([])

          subject.handle(event)
        end

        it "clears the package details" do
          expect(package_details).to receive(:clear)

          subject.handle(event)
        end
      end
    end

    context "when a package is selected for installation" do
      let(:event) { { "WidgetID" => "remote_packages_table", "EventReason" => "Activated" } }

      before do
        allow(subject).to receive(:packages).and_return([package])
      end

      it "toggles the selected package" do
        expect(controller).to receive(:toggle_package).with(package)
        subject.handle(event)
      end

      it "updates the table and the package details" do
        allow(Yast2::Popup).to receive(:show)
        expect(packages_table).to receive(:update_item).with(package)
        expect(package_details).to receive(:update).with(package)
        subject.handle(event)
      end
    end

    context "when the user selects a different package in the table" do
      let(:event) { { "WidgetID" => "remote_packages_table", "EventReason" => "SelectionChanged" } }

      before do
        allow(subject).to receive(:packages).and_return([package])
      end

      it "updates the package details" do
        expect(package_details).to receive(:update).with(package)
        subject.handle(event)
      end
    end
  end
end
