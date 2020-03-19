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
require "registration/widgets/search_results_info"

require "cwm/rspec"

describe Registration::Widgets::SearchResultsInfo do
  subject { described_class.new }

  include_examples "CWM::CustomWidget"

  describe "#update" do
    context "when search does not return pacakges" do
      it "uses a no package info message" do
        expect(Yast::UI).to receive(:ChangeWidget).with(anything, :Value, /No package found/)

        subject.update(0)
      end
    end

    context "when search returns just one package" do
      it "uses the singular form of the info message" do
        expect(Yast::UI).to receive(:ChangeWidget).with(anything, :Value, /package found/)

        subject.update(1)
      end
    end

    context "when search returns more than one package" do
      it "uses the plural form of the info message" do
        expect(Yast::UI).to receive(:ChangeWidget).with(anything, :Value, /packages found/)

        subject.update(2)
      end
    end
  end
end
