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
require "registration/widgets/checkbox_list"

describe Registration::Widgets::CheckboxList do
  subject { described_class.new(initial_content: initial_content) }

  let(:id) { "something" }
  let(:initial_content) { "Initial content for testing" }
  let(:vscroll) { 15 }

  include_examples "CWM::RichText"

  before do
    allow(subject).to receive(:Id).and_return("something")
  end

  describe "#init" do
    it "sets the initial content" do
      expect(Yast::UI).to receive(:ChangeWidget).with(id, :Value, initial_content)

      subject.init
    end
  end

  describe "update" do
    let(:content) { "Content to test the #update method" }

    before do
      allow(Yast::UI).to receive(:QueryWidget).with(id, :VScrollValue).and_return(vscroll)
      allow(Yast::UI).to receive(:ChangeWidget).with(id, :VScrollValue, vscroll)
      allow(Yast::UI).to receive(:ChangeWidget).with(id, :Value, content)
    end

    it "sets given content" do
      expect(Yast::UI).to receive(:ChangeWidget).with(id, :Value, content)

      subject.update(content)
    end

    it "saves the vertical scroll value" do
      expect(Yast::UI).to receive(:QueryWidget).with(id, :VScrollValue)

      subject.update(content)
    end

    it "restores the vertical scroll value" do
      expect(Yast::UI).to receive(:ChangeWidget).with(id, :VScrollValue, vscroll)

      subject.update(content)
    end
  end
end
