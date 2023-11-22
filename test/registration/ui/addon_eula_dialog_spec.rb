#!/usr/bin/env rspec
# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE LLC, All Rights Reserved.
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
  subject(:eula_dialog) { described_class.new(addons) }

  let(:params) { { "eula_url" => "http://example.addon-eula.url" } }
  let(:addons) { [registered_addon, addon_wo_eula, addon_with_eula] }

  let(:addon_wo_eula) { Registration::Addon.new(addon_generator) }
  let(:addon_with_eula) { Registration::Addon.new(addon_generator(params)) }
  let(:second_addon_with_eula) { Registration::Addon.new(addon_generator(params)) }
  let(:registered_addon) { Registration::Addon.new(addon_generator(params)) }

  before do
    allow(eula_dialog).to receive(:download_eula).and_return(true)
    registered_addon.registered
  end

  describe "#run" do
    before do
      allow(Yast::Wizard).to receive(:SetContents)
    end

    context "when there are no EULA acceptances to show" do
      let(:addons) { [registered_addon, addon_wo_eula] }

      it "does not display the eula dialog" do
        expect(Yast::ProductLicense).to_not receive(:DisplayLicenseDialogWithTitle)

        eula_dialog.run
      end

      it "returns :next" do
        expect(eula_dialog.run).to eq(:next)
      end
    end

    context "when there are EULA acceptances pending" do
      let(:addons) { [addon_with_eula, second_addon_with_eula] }
      let(:first_dialog_response) { :refused }
      let(:second_dialog_response) { :accepted }

      before do
        allow(Yast::ProductLicense).to receive(:HandleLicenseDialogRet)
          .and_return(first_dialog_response, second_dialog_response)
        allow(Yast::ProductLicense).to receive(:DisplayLicenseDialogWithTitle)
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
          allow(eula_dialog).to receive(:download_eula).and_return(false)
        end

        it "does not display the eula dialog" do
          expect(Yast::ProductLicense).to_not receive(:DisplayLicenseDialogWithTitle)

          eula_dialog.run
        end

        it "returns :back" do
          expect(eula_dialog.run).to eq(:back)
        end
      end
    end

    context "when EULA is accepted" do
      let(:addons) { [addon_with_eula] }

      before do
        allow(Yast::ProductLicense).to receive(:HandleLicenseDialogRet)
          .and_return(:accepted)
        allow(Yast::ProductLicense).to receive(:DisplayLicenseDialogWithTitle)
      end

      it "sets it as accepted" do
        expect { eula_dialog.run }.to change { addon_with_eula.eula_accepted? }.from(false).to(true)
      end

      it "returns :next" do
        expect(eula_dialog.run).to eq(:next)
      end
    end

    context "when EULA is refused" do
      let(:addons) { [addon_with_eula] }

      before do
        allow(Yast::ProductLicense).to receive(:HandleLicenseDialogRet)
          .and_return(:refused)
        allow(Yast::ProductLicense).to receive(:DisplayLicenseDialogWithTitle)
      end

      it "does not set it as accepted" do
        expect { eula_dialog.run }.to_not change { addon_with_eula.eula_accepted? }
      end

      it "returns :next" do
        expect(eula_dialog.run).to eq(:next)
      end
    end
  end
end
