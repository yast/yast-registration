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
  subject { described_class.new(registration) }

  include_examples "CWM::Dialog"

  let(:an_addon) { addon_generator }
  let(:another_addon) { addon_generator }
  let(:addons_list) { [an_addon, another_addon] }
  let(:selected_addons) { [] }

  let(:controller) do
    Registration::Controllers::AddonsSelection.new(registration)
  end

  let(:registration) do
    instance_double(Registration::Registration, activated_products: [], get_addon_list: addons_list)
  end

  shared_examples "restores selection and aborts" do
    context "when running in the initial stage" do
      let(:abort_confirmation) { false }

      before do
        allow(Yast::Stage).to receive(:initial).and_return(true)
        allow(Registration::UI::AbortConfirmation).to receive(:run).and_return(abort_confirmation)
      end

      it "asks for confirmation" do
        expect(Registration::UI::AbortConfirmation).to receive(:run)

        subject.run
      end

      context "and the user confirms the action" do
        let(:abort_confirmation) { true }

        it "returns :abort" do
          expect(subject.run).to eq(:abort)
        end
      end

      context "but the user cancels the action" do
        let(:abort_confirmation) { false }

        it "returns nil" do
          expect(subject.run).to be_nil
        end
      end
    end

    it "restores the selection" do
      expect(controller).to receive(:restore_selection)

      subject.run
    end

    it "returns :abort" do
      expect(subject.run).to eq(:abort)
    end
  end

  describe "#contents" do
    it "contains a heading" do
      found = subject.contents.nested_find { |w| w.is_a?(Yast::Term) && w.value == :Heading }

      expect(found).to_not be_nil
    end

    it "contains a MasterDetailSelector widget" do
      found = subject.contents.nested_find do |w|
        w.is_a?(Registration::Widgets::MasterDetailSelector)
      end

      expect(found).to_not be_nil
    end
  end

  describe "#run" do
    before do
      allow(subject).to receive(:cwm_show).and_return(result)
      allow(Registration::Controllers::AddonsSelection).to receive(:new).and_return(controller)
    end

    context "when some addons were selected" do
      before do
        allow(Registration::Addon).to receive(:selected).and_return([an_addon])
      end

      let(:selected_addons) { [an_addon] }

      context "and the user clicks next" do
        let(:result) { :next }

        it "returns :next" do
          expect(subject.run).to eq(:next)
        end
      end

      context "and the user clicks cancel" do
        let(:result) { :cancel }

        include_examples "restores selection and aborts"
      end

      context "and the user clicks abort" do
        let(:result) { :cancel }

        include_examples "restores selection and aborts"
      end
    end

    context "when no addons is selected" do
      before do
        allow(Registration::Addon).to receive(:selected).and_return([])
      end

      context "and the user clicks next" do
        let(:result) { :next }

        it "returns :skip" do
          expect(subject.run).to eq(:skip)
        end
      end
    end
  end
end
