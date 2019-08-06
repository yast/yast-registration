#!/usr/bin/env rspec
# ------------------------------------------------------------------------------
# Copyright (c) 2018 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require_relative "../../spec_helper"
require "registration/ui/addon_eula_dialog"

describe Registration::UI::AddonEulaDialog do
  subject(:dialog) { described_class.new(addons) }

  let(:params) { { "eula_url" => "http://example.addon-eula.url" } }
  let(:addons) { [registered_addon, addon_wo_eula, addon_with_eula] }

  let(:addon_wo_eula) { Registration::Addon.new(addon_generator) }
  let(:addon_with_eula) { Registration::Addon.new(addon_generator(params)) }
  let(:second_addon_with_eula) { Registration::Addon.new(addon_generator(params)) }
  let(:registered_addon) { Registration::Addon.new(addon_generator(params)) }

  let(:product_license) do
    instance_double(Y2Packager::ProductLicense, accepted?: false, accept!: true)
  end

  describe "#run" do
    before do
      allow(Yast::Wizard).to receive(:SetContents)
      allow(dialog).to receive(:find_license).and_return(product_license)
      allow(dialog).to receive(:download_eula).and_return(true)
      registered_addon.registered
    end

    after do
      Registration::Addon.reset!
    end

    context "when there are no EULA acceptances to show" do
      let(:addons) { [registered_addon, addon_wo_eula] }

      it "does not display the EULA dialog" do
        expect(Yast::ProductLicense).to_not receive(:DisplayLicenseDialogWithTitle)

        dialog.run
      end

      it "returns :next" do
        expect(dialog.run).to eq(:next)
      end
    end

    context "when there are EULA acceptances pending" do
      let(:addons) { [addon_with_eula, second_addon_with_eula] }
      let(:first_dialog_response) { :refused }
      let(:second_dialog_response) { :accepted }

      before do
        allow(Yast::ProductLicense).to receive(:HandleLicenseDialogRet)
          .and_return(first_dialog_response, second_dialog_response)
      end

      context "and the user wants to go back" do
        let(:first_dialog_response) { :back }

        it "returns :back" do
          expect(subject.run).to eq(:back)
        end
      end

      context "and the user wants to abort" do
        let(:first_dialog_response) { :abort }

        it "returns :abort" do
          expect(subject.run).to eq(:abort)
        end
      end

      context "but an EULA cannot be downloaded" do
        before do
          allow(dialog).to receive(:download_eula).and_return(false)
        end

        it "does not display the eula dialog" do
          expect(Yast::ProductLicense).to_not receive(:DisplayLicenseDialogWithTitle)

          dialog.run
        end

        it "returns :back" do
          expect(dialog.run).to eq(:back)
        end
      end
    end

    context "when EULA is accepted" do
      let(:addons) { [addon_with_eula] }

      before do
        allow(Yast::ProductLicense).to receive(:HandleLicenseDialogRet)
          .and_return(:accepted)
      end

      it "sets it as accepted" do
        expect(product_license).to receive(:accept!)

        subject.run
      end

      it "returns :next" do
        expect(dialog.run).to eq(:next)

        subject.run
      end
    end

    context "when EULA is refused" do
      let(:addons) { [addon_with_eula] }

      before do
        allow(Yast::ProductLicense).to receive(:HandleLicenseDialogRet)
          .and_return(:refused)
      end

      it "does not set it as accepted" do
        expect(product_license).to_not receive(:accept!)
      end

      it "returns :next" do
        expect(dialog.run).to eq(:next)
      end
    end
  end

  describe "#accept_eula" do
    let(:addon) do
      addon_generator("name" => "SLES", "eula_url" => "https://suse.com/download/SLES/eula")
    end
    let(:addons) { [addon] }
    let(:eula_downloader) { instance_double(Registration::EulaDownloader, download: true) }
    let(:eula_reader) { instance_double(Registration::EulaReader, licenses: licenses_files) }
    let(:licenses_files) do
      { Y2Packager::License::DEFAULT_LANG => "license.txt" }
    end
    let(:accepted?) { true }
    let(:product_license) { instance_double(Y2Packager::ProductLicense, accepted?: accepted?) }
    let(:license_content) { "content" }

    before do
      allow(Registration::EulaDownloader).to receive(:new).and_return(eula_downloader)
      allow(Registration::EulaReader).to receive(:new).and_return(eula_reader)
      allow(Y2Packager::ProductLicense).to receive(:find).and_return(product_license)
      allow(Yast::SCR).to receive(:Read).with(Yast::Path.new(".target.string"), "license.txt")
        .and_return(license_content)
      allow(dialog).to receive(:setup_eula_dialog)
      allow(dialog).to receive(:run_eula_dialog)
    end

    context "when the eula could not be downloaded" do
      before do
        allow(eula_downloader).to receive(:download).and_raise(StandardError)
      end

      it "returns :back" do
        expect(dialog.send(:accept_eula, addon)).to eq(:back)
      end
    end

    it "reads the license and asks for a already seen license with the same content" do
      expect(Y2Packager::ProductLicense).to receive(:find)
        .with(addon.identifier, content: "content").and_return(product_license)
      dialog.send(:accept_eula, addon)
    end

    context "when the license file is not defined" do
      let(:licenses_files) { {} }

      it "does not ask for already seen licenses" do
        expect(Y2Packager::ProductLicense).to_not receive(:find)
        dialog.send(:accept_eula, addon)
      end
    end

    context "when license file could not be read" do
      let(:license_content) { nil }

      it "does not ask for already seen licenses" do
        expect(Y2Packager::ProductLicense).to_not receive(:find)
        dialog.send(:accept_eula, addon)
      end
    end

    context "when the license was previously accepted" do
      let(:accepted?) { true }

      it "returns :next" do
        expect(dialog.send(:accept_eula, addon)).to eq(:next)
      end

      it "does not show the eula" do
        expect(subject).to_not receive(:run_eula_dialog)
        dialog.send(:accept_eula, addon)
      end
    end

    context "when the license was not previously accepted" do
      let(:accepted?) { false }

      it "shows the eula" do
        expect(subject).to receive(:run_eula_dialog)
        dialog.send(:accept_eula, addon)
      end
    end
  end
end
