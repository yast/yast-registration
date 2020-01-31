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
    it "returns the list of packages from SCC" do
      expect(controller.search(text)).to eq([package])
    end
  end

  describe "#toggle_package" do
    context "when the package is not selected for installation" do
      context "and the addon is already registered" do
        before do
          allow(addon).to receive(:registered?).and_return(true)
        end

        it "adds the package to the list of packages to install" do
          subject.toggle_package(package)
          expect(subject.selected_packages).to eq([package])
        end
      end

      context "when the addon is not registered" do
        before do
          allow(Yast2::Popup).to receive(:show).and_return(register?)
        end

        let(:addon) do
          pure_addon = load_yaml_fixture("pure_addons.yml").first
          Registration::Addon.new(pure_addon)
        end

        context "but the user accepts to register the addon" do
          let(:register?) { :yes }

          it "adds the package to the list of packages to install" do
            subject.toggle_package(package)
            expect(subject.selected_packages).to eq([package])
          end

          it "selects the addon for registration" do
            expect(addon).to receive(:selected)
            subject.toggle_package(package)
          end
        end

        context "and the user refuses to register the addon" do
          let(:register?) { :no }

          it "does not add the package to the list of packages to install" do
            subject.toggle_package(package)
            expect(subject.selected_packages).to eq([])
          end

          it "does not select the addon for registration" do
            expect(addon).to_not receive(:selected)
            subject.toggle_package(package)
          end
        end
      end

      context "when the addon is selected for registration" do
        before do
          allow(addon).to receive(:selected?).and_return(true)
        end

        it "does not ask about registering the addon" do
          expect(Yast2::Popup).to_not receive(:show)
          subject.toggle_package(package)
        end

        it "adds the package to the list of packages to install" do
          subject.toggle_package(package)
          expect(subject.selected_packages).to eq([package])
        end
      end

      context "when the addon is auto selected for registration" do
        let(:addon) do
          pure_addon = load_yaml_fixture("pure_addons.yml").first
          Registration::Addon.new(pure_addon)
        end

        before do
          allow(addon).to receive(:auto_selected?).and_return(true)
        end

        it "does not ask about registering the addon" do
          expect(Yast2::Popup).to_not receive(:show)
          subject.toggle_package(package)
        end

        it "selects the addon" do
          expect(addon).to receive(:selected)
          subject.toggle_package(package)
        end

        it "adds the package to the list of packages to install" do
          subject.toggle_package(package)
          expect(subject.selected_packages).to eq([package])
        end
      end
    end

    context "when the package is already selected for installation" do
      context "and the package is already selected" do
        let(:package) do
          instance_double(
            Registration::RemotePackage, id: 1, name: "gnome-desktop", addon: addon,
            selected?: true, unselect!: nil, installed?: false
          )
        end

        it "unselects the package" do
          allow(Yast2::Popup).to receive(:show).and_return(:yes)
          expect(package).to receive(:unselect!)
          subject.toggle_package(package)
        end

        context "and the addon is still needed" do
          let(:another_package) do
            instance_double(Registration::RemotePackage, name: "eog", addon: addon)
          end

          before do
            allow(subject).to receive(:selected_packages).and_return([package, another_package])
          end

          it "does not unselect the addon" do
            expect(addon).to_not receive(:unselected)
            subject.toggle_package(package)
          end
        end

        context "and the addon is not needed anymore" do
          before do
            allow(Yast2::Popup).to receive(:show).and_return(unselect?)
          end

          context "and the user agrees to unselect it" do
            let(:unselect?) { :yes }

            it "unselects the addon" do
              expect(addon).to receive(:unselected)
              subject.toggle_package(package)
            end
          end

          context "and the user wants to keep the addon" do
            let(:unselect?) { :no }

            it "does not unselect the addon" do
              expect(addon).to_not receive(:unselected)
              subject.toggle_package(package)
            end
          end
        end
      end
    end

    context "when an already installed package is selected for installation" do
      let(:installed?) { true }

      before do
        allow(addon).to receive(:registered?).and_return(true)
      end

      it "does not select the package" do
        subject.toggle_package(package)
        expect(subject.selected_packages).to be_empty
      end
    end

  end
end
