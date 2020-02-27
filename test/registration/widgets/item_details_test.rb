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
require "registration/widgets/item_details"

describe Registration::Widgets::ItemDetails do
  include_examples "CWM::RichText"

  describe "#init" do
    context "if a placeholder has been defined" do
      subject { described_class.new(placeholder: placeholder) }
      let(:placeholder) { "A text used as a placeholder" }

      it "displays the placeholder" do
        expect(subject).to receive(:value=).with(placeholder)

        subject.init
      end
    end

    context "when a placeholder was not defined" do
      it "displays nothing" do
        expect(subject).to receive(:value=).with("")

        subject.init
      end
    end
  end

  describe "#update" do
    let(:content) { "Details about an item" }

    it "displays given content" do
      expect(subject).to receive(:value=).with("Details about an item")

      subject.update(content)
    end
  end

  describe "#reset" do
    it "disables itself" do
      expect(subject).to receive(:disable)

      subject.reset
    end

    context "if a placeholder has been defined" do
      subject { described_class.new(placeholder: placeholder) }
      let(:placeholder) { "A text used as a placeholder" }

      it "displays the placeholder" do
        expect(subject).to receive(:value=).with(placeholder)

        subject.reset
      end
    end

    context "when a placeholder hast not been defined" do
      it "displays nothing" do
        expect(subject).to receive(:value=).with("")

        subject.reset
      end
    end
  end
end
