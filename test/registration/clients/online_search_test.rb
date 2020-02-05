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
require "registration/clients/online_search"
require "registration/remote_package"

describe Registration::Clients::OnlineSearch do
  describe "#run" do
    let(:search_dialog) do
      instance_double(
        Registration::Dialogs::OnlineSearch, run: search_result, selected_packages: [package]
      )
    end

    let(:registration_ui) do
      instance_double(Registration::RegistrationUI, register_addons: registration_result)
    end

    let(:package) { instance_double(Registration::RemotePackage, name: "gnome-desktop") }
    let(:search_result) { :next }
    let(:registration_result) { :next }
    let(:registration_url) { SUSE::Connect::YaST::DEFAULT_URL }

    before do
      allow(Registration::Addon).to receive(:find_all)
      allow(Registration::Dialogs::OnlineSearch).to receive(:new).and_return(search_dialog)
      allow(Registration::Dialogs::OnlineSearchSummary).to receive(:run).and_return(:next)
      allow(Registration::RegistrationUI).to receive(:new).and_return(registration_ui)
      allow(Registration::UI::AddonEulaDialog).to receive(:run).and_return(:next)
      allow(Registration::SwMgmt).to receive(:select_addon_products)
      allow(Registration::UrlHelpers).to receive(:registration_url)
        .and_return(registration_url) # speed up the test
      allow(Yast::Pkg).to receive(:PkgInstall).and_return(true)
      allow(Registration::Registration).to receive(:is_registered?).and_return(true)
    end

    context "when an addon is selected" do
      let(:addon_1) do
        instance_double(Registration::Addon, depends_on: [], eula_acceptance_needed?: false)
      end
      let(:addon_2) do
        instance_double(Registration::Addon, depends_on: [], eula_acceptance_needed?: false)
      end

      before do
        allow(Registration::Addon).to receive(:selected).and_return([addon_1])
        allow(Registration::Addon).to receive(:auto_selected).and_return([addon_2])
      end

      it "registers the addon" do
        expect(registration_ui).to receive(:register_addons).with([addon_1, addon_2], {})
        subject.run
      end

      it "selects the addon product package" do
        expect(Registration::SwMgmt).to receive(:select_addon_products)
        subject.run
      end

      context "when accepting an EULA is required" do
        let(:addon_1) do
          instance_double(Registration::Addon, depends_on: [], eula_acceptance_needed?: true)
        end

        it "asks for EULA acceptance" do
          expect(::Registration::UI::AddonEulaDialog).to receive(:run)
            .with([addon_1, addon_2]).and_return(:next)
          expect(registration_ui).to receive(:register_addons).with([addon_1, addon_2], {})
          subject.run
        end
      end

      context "when the addon registration fails" do
        let(:registration_result) { :abort }

        it "returns :abort" do
          expect(subject.run).to eq(:abort)
        end

        it "does not select any package" do
          expect(Yast::Pkg).to_not receive(:PkgInstall)
          subject.run
        end
      end
    end

    context "when no addons are selected" do
      before do
        allow(Registration::Addon).to receive(:selected).and_return([])
        allow(Registration::Addon).to receive(:auto_selected).and_return([])
      end

      it "does not register any addon" do
        expect(registration_ui).to_not receive(:register_addons)
        subject.run
      end
    end

    context "when a package is selected" do
      it "selects the package for installation" do
        expect(Yast::Pkg).to receive(:PkgInstall).with(package.name).and_return(true)
        subject.run
      end

      context "but the package is not found" do
        before do
          allow(Yast::Pkg).to receive(:PkgInstall).and_return(false)
        end

        it "warns the user" do
          expect(Yast2::Popup).to receive(:show).with(/could not be selected/, headline: :error)
          subject.run
        end
      end
    end

    context "when the user aborts the search" do
      let(:search_result) { :abort }

      it "returns :abort" do
        expect(subject.run).to eq(:abort)
      end
    end

    context "when the system is not registered" do
      before do
        allow(Registration::Registration).to receive(:is_registered?).and_return(false)
        allow(Yast2::Popup).to receive(:show)
      end

      it "displays a message" do
        expect(Yast2::Popup).to receive(:show).with(/to be registered/, headline: :error)
        subject.run
      end

      it "returns :abort" do
        expect(subject.run).to eq(:abort)
      end
    end

    context "when an SMT/RMT server was used" do
      let(:registration_url) { "https://smt.example.net" }

      before do
        allow(Yast2::Popup).to receive(:show)
      end

      it "displays a message" do
        expect(Yast2::Popup).to receive(:show).with(/SMT/, headline: :error)
        subject.run
      end

      it "returns :abort" do
        expect(subject.run).to eq(:abort)
      end
    end
  end
end
