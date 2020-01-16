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

  let(:packages_table) do
    instance_double(
      Registration::Widgets::RemotePackagesTable, value: package.name, change_items: nil,
      selected_item: package
    )
  end

  let(:package_details) do
    instance_double(Registration::Widgets::RemotePackageDetails, update: nil)
  end

  let(:package) do
    instance_double(
      Registration::RemotePackage, name: "gnome-desktop", addon: addon,
      selected?: false, select!: nil
    )
  end

  let(:addon) do
    instance_double(
      Registration::Addon, name: "desktop", registered?: false, selected?: false, selected: nil
    )
  end

  let(:search) do
    instance_double(Registration::PackageSearch, packages: [package])
  end

  before do
    allow(Registration::Widgets::RemotePackagesTable).to receive(:new)
      .and_return(packages_table)
    allow(Registration::Widgets::RemotePackageDetails).to receive(:new)
      .and_return(package_details)
    allow(subject).to receive(:search).and_return(search)
  end

  describe "#handle" do
    context "when the user asks for a package" do
      let(:event) { { "WidgetID" => "search_form_button" } }

      let(:search_form) do
        instance_double(Registration::Widgets::PackageSearchForm, text: "gnome")
      end

      before do
        allow(Registration::Widgets::PackageSearchForm).to receive(:new)
          .and_return(search_form)
        allow(Registration::PackageSearch).to receive(:new).and_return(search)
      end

      it "searches for the package in SCC" do
        expect(Registration::PackageSearch).to receive(:new)
          .with(text: "gnome").and_return(search)
        subject.handle(event)
      end

      it "updates the table and the package details" do
        expect(packages_table).to receive(:change_items).with([package])
        expect(package_details).to receive(:update).with(package)
        subject.handle(event)
      end
    end

    context "when a package is selected for installation" do
      let(:event) { { "WidgetID" => "remote_packages_table", "EventReason" => "Activated" } }

      context "and the addon is already registered" do
        before do
          allow(addon).to receive(:registered?).and_return(true)
        end

        it "adds the package to the list of packages to install" do
          subject.handle(event)
          expect(subject.selected_packages).to eq([package])
        end
      end

      context "when the addon is not registered" do
        before do
          allow(Yast::Popup).to receive(:YesNo).and_return(register?)
        end

        context "but the user accepts to register the addon" do
          let(:register?) { true }

          it "adds the package to the list of packages to install" do
            subject.handle(event)
            expect(subject.selected_packages).to eq([package])
          end

          it "selects the addon for registration" do
            expect(addon).to receive(:selected)
            subject.handle(event)
          end
        end

        context "and the user refuses to register the addon" do
          let(:register?) { false }

          it "does not add the package to the list of packages to install" do
            subject.handle(event)
            expect(subject.selected_packages).to eq([])
          end

          it "does not select the addon for registration" do
            expect(addon).to_not receive(:selected)
            subject.handle(event)
          end
        end
      end

      context "when the addon is selected for registration" do
        before do
          allow(addon).to receive(:selected?).and_return(true)
        end

        it "does not ask about registering the addon" do
          expect(Yast::Popup).to_not receive(:YesNo)
          subject.handle(event)
        end

        it "adds the package to the list of packages to install" do
          subject.handle(event)
          expect(subject.selected_packages).to eq([package])
        end
      end
    end

    context "when the user selects a different package in the table" do
      let(:event) { { "WidgetID" => "remote_packages_table", "EventReason" => "SelectionChanged" } }

      it "updates the package details" do
        expect(package_details).to receive(:update).with(package)
        subject.handle(event)
      end
    end
  end
end