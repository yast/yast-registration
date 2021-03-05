#!/usr/bin/env rspec
# Copyright (c) [2021] SUSE LLC
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
require "registration/ui/registered_system_dialog"

describe Registration::UI::RegisteredSystemDialog do
  include Yast::UIShortcuts

  subject(:dialog) { described_class.new(extensions: extensions, registration: registration) }

  let(:extensions) { true }
  let(:registration) { true }

  describe ".run" do
    let(:dialog) { double(Registration::UI::RegisteredSystemDialog, run: true) }

    before do
      allow(described_class).to receive(:new).and_return(dialog)
    end

    it "creates an instance of the dialog" do
      expect(described_class).to receive(:new)

      described_class.run
    end

    it "runs the dialog" do
      expect(dialog).to receive(:run)

      described_class.run
    end
  end

  describe "#run" do
    let(:mode) { "installation" }
    let(:user_input) { :cancel }

    before do
      allow(Yast::Wizard).to receive(:SetContents)
      allow(Yast::Wizard).to receive(:SetNextButton)
      allow(Yast::Wizard).to receive(:RestoreNextButton)

      allow(Yast::Mode).to receive(:mode).and_return(mode)

      allow(Yast::UI).to receive(:ChangeWidget)
      allow(Yast::UI).to receive(:UserInput).and_return(user_input)
    end

    it "returns the user input" do
      expect(subject.run).to eq(:cancel)
    end

    it "does not change the next button label" do
      expect(Yast::Wizard).to_not receive(:SetNextButton)
    end

    it "keeps 'Select Extensions' button enabled" do
      expect(Yast::UI).to_not receive(:ChangeWidget).with(Id(:extensions), :Enabled, false)

      subject.run
    end

    it "includes help for 'Select Extensions' button" do
      expect(Yast::Wizard).to receive(:SetContents).with(
        anything,
        anything,
        /register additional extension/,
        any_args
      )

      subject.run
    end

    it "keeps 'Register Again' button enabled" do
      expect(Yast::UI).to_not receive(:ChangeWidget).with(Id(:register), :Enabled, false)

      subject.run
    end

    it "includes help for 'Register Again' button" do
      expect(Yast::Wizard).to receive(:SetContents).with(
        anything,
        anything,
        /re-register the system again/,
        any_args
      )

      subject.run
    end

    context "when running in normal mode" do
      let(:mode) { "normal" }

      it "changes the next button label" do
        expect(Yast::Wizard).to receive(:SetNextButton)

        subject.run
      end
    end

    context "when extensions are not enabled" do
      let(:extensions) { false }

      it "disables 'Select Extensions' button" do
        expect(Yast::UI).to receive(:ChangeWidget).with(Id(:extensions), :Enabled, false)

        subject.run
      end

      it "does not include help for it" do
        expect(Yast::Wizard).to_not receive(:SetContents).with(
          anything,
          anything,
          /register additional extension/,
          any_args
        )

        subject.run
      end
    end

    context "when register is not enabled" do
      let(:registration) { false }

      it "disables 'Register Again' button" do
        expect(Yast::UI).to receive(:ChangeWidget).with(Id(:register), :Enabled, false)

        subject.run
      end

      it "does not include help for it" do
        expect(Yast::Wizard).to_not receive(:SetContents).with(
          anything,
          anything,
          /re-register the system again/,
          any_args
        )

        subject.run
      end
    end
  end
end
