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
require "registration/widgets/toggle_package_selection"

describe Registration::Widgets::TogglePackageSelection do
  include Yast::UIShortcuts

  subject { described_class.new }

  include_examples "CWM::PushButton"

  let(:id) { Id(subject.widget_id) }

  describe "#enabled=" do
    context "when `true` is given" do
      it "sets the button as enabled " do
        expect(Yast::UI).to receive(:ChangeWidget).with(id, :Enabled, true)

        subject.enabled = true
      end
    end

    context "when `false` is given" do
      it "sets the button as disabled " do
        expect(Yast::UI).to receive(:ChangeWidget).with(id, :Enabled, false)

        subject.enabled = false
      end
    end
  end
end
