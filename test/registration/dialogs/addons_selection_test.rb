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

require "cwm/rspec"
require "registration/dialogs/addons_selection"

describe Registration::Dialogs::AddonsSelection do
  subject(:dialog) { described_class.new(registration) }

  include_examples "CWM::Dialog"

  let(:addons) { load_yaml_fixture("sle15_addons.yaml") }
  let(:sle_we_addon) { addons.find { |a| a.identifier == "sle-we" } }
  let(:basesystem_module_addon) { addons.find { |a| a.identifier == "sle-module-basesystem" } }
  let(:recommend_basesystem_module) { true }

  let(:registration) do
    instance_double(
      Registration::Registration,
      activated_products: [], get_addon_list: [sle_we_addon, basesystem_module_addon]
    )
  end

  before do
    addon_reset_cache
    allow(Registration::Addon).to receive(:find_all).and_return(addons)
    allow(basesystem_module_addon).to receive(:recommended).and_return(recommend_basesystem_module)
  end

  describe "#initialize" do
    context "when there are not selected or registered addon yet" do
      it "preselects recommended addons" do
        expect(basesystem_module_addon).to receive(:selected)

        subject
      end
    end

    context "there is any addon already selected" do
      before do
        allow(Registration::Addon).to receive(:selected).and_return([sle_we_addon])
      end

      it "does not preselect recommended addons" do
        expect(basesystem_module_addon).to_not receive(:selected)

        subject
      end
    end

    context "there is any addon already registered" do
      before do
        allow(Registration::Addon).to receive(:registered).and_return([sle_we_addon])
      end

      it "does not preselect recommended addons" do
        expect(basesystem_module_addon).to_not receive(:selected)

        subject
      end
    end
  end

  describe "#run" do
    let(:recommend_basesystem_module) { false }

    before do
      allow_any_instance_of(CWM::Dialog).to receive(:run).and_return(dialog_result)
    end

    shared_examples "canceling or aborting the dialog" do
      context "and running in initial stage" do
        before do
          sle_we_addon.selected # initially selected
          allow(Yast::Stage).to receive(:initial).and_return(true)
        end

        context "and the user confirms the action" do
          before do
            allow(Registration::UI::AbortConfirmation).to receive(:run).and_return(true)
          end

          it "undoes the current selection by restoring the initial one" do
            # initialize the dialog
            subject

            # performs a selection
            basesystem_module_addon.selected

            # cancel
            subject.run

            # initial selection should be restored
            expect(Registration::Addon.selected).to eq([sle_we_addon])
          end

          it "returns :abort" do
            expect(subject.run).to eq(:abort)
          end
        end

        context "but the user cancels the action" do
          before do
            allow(Registration::UI::AbortConfirmation).to receive(:run).and_return(false)
          end

          it "returns nil" do
            expect(subject.run).to eq(nil)
          end
        end
      end
    end

    context "when the user decides to continue" do
      let(:dialog_result) { :next }

      context "and there is none addon selected" do
        before do
          allow(Registration::Addon).to receive(:selected).and_return([])
        end

        it "returns :skip" do
          expect(subject.run).to eq(:skip)
        end
      end

      context "and there are some addons selected" do
        before do
          allow(Registration::Addon).to receive(:selected).and_return([sle_we_addon])
        end

        it "returns :next" do
          expect(subject.run).to eq(:next)
        end
      end
    end

    context "when the user decides to cancel" do
      let(:dialog_result) { :cancel }

      include_examples "canceling or aborting the dialog"
    end

    context "when the user decides to abort" do
      let(:dialog_result) { :abort }

      include_examples "canceling or aborting the dialog"
    end
  end
end
