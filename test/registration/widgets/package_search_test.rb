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
      Registration::Widgets::RemotePackagesTable, value: package.id,
      change_items: nil, update_item: nil
    )
  end

  let(:package_details) do
    instance_double(Registration::Widgets::RemotePackageDetails, update: nil)
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
      let(:text) { "gnome" }

      let(:search_form) do
        instance_double(Registration::Widgets::PackageSearchForm, text: text)
      end

      before do
        allow(Registration::Widgets::PackageSearchForm).to receive(:new)
          .and_return(search_form)
        allow(Registration::PackageSearch).to receive(:new).and_return(search)
      end

      it "searches for the package in SCC" do
        expect(Registration::PackageSearch).to receive(:new)
          .with(text: text).and_return(search)
        subject.handle(event)
      end

      it "updates the table and the package details" do
        expect(packages_table).to receive(:change_items).with([package])
        expect(package_details).to receive(:update).with(package)
        subject.handle(event)
      end

      context "when the search text is not enough" do
        let(:text) { "g" }

        it "asks the user to introduce some text" do
          expect(Yast2::Popup).to receive(:show)
            .with(/at least/)
          subject.handle(event)
        end
      end
    end

    context "when a package is selected for installation" do
      let(:event) { { "WidgetID" => "remote_packages_table", "EventReason" => "Activated" } }

      context "and the package is already selected" do
        let(:package) do
          instance_double(
            Registration::RemotePackage, id: 1, name: "gnome-desktop", addon: addon,
            selected?: true, unselect!: nil, installed?: false
          )
        end

        it "unselects the package" do
          expect(package).to receive(:unselect!)
          subject.handle(event)
        end

        context "and the addon is still needed" do
          let(:another_package) do
            instance_double(Registration::RemotePackage, name: "eog", addon: addon)
          end

          before do
            allow(subject).to receive(:selected_packages).and_return([package, another_package])
            subject.handle(event)
          end

          it "does not unselect the addon" do
            expect(Yast::Popup).to_not receive(:YesNo)
            expect(addon).to_not receive(:unselected)
            subject.handle(event)
          end
        end

        context "and the addon is not needed anymore" do
          before do
            allow(Yast::Popup).to receive(:YesNo).and_return(unselect?)
          end

          context "and the user agrees to unselect it" do
            let(:unselect?) { true }

            it "unselects the addon" do
              expect(addon).to receive(:unselected)
              subject.handle(event)
            end
          end

          context "and the user wants to keep the addon" do
            let(:unselect?) { false }

            it "does not unselect the addon" do
              expect(addon).to_not receive(:unselected)
              subject.handle(event)
            end
          end
        end
      end

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

        let(:addon) do
          pure_addon = load_yaml_fixture("pure_addons.yml").first
          Registration::Addon.new(pure_addon)
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

      it "updates the table and the package details" do
        expect(packages_table).to receive(:update_item).with(package)
        expect(package_details).to receive(:update).with(package)
        subject.handle(event)
      end
    end

    context "when an already installed package is selected for installation" do
      let(:event) { { "WidgetID" => "remote_packages_table", "EventReason" => "Activated" } }
      let(:installed?) { true }

      before do
        allow(addon).to receive(:registered?).and_return(true)
      end

      it "does not select the package" do
        subject.handle(event)
        expect(subject.selected_packages).to be_empty
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
