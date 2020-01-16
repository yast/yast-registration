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
require "registration/widgets/package_search_form"

require "cwm/rspec"

describe Registration::Widgets::PackageSearchForm do
  include Yast::UIShortcuts

  include_examples "CWM::CustomWidget"

  describe "#text" do
    before do
      allow(Yast::UI).to receive(:QueryWidget)
        .with(Id("search_form_text"), :Value).and_return("foo")
    end

    it "returns the content of the text widget" do
      expect(subject.text).to eq("foo")
    end
  end

  describe "#ignore_case" do
    before do
      allow(Yast::UI).to receive(:QueryWidget)
        .with(Id("search_form_ignore_case"), :Value).and_return(true)
    end

    it "returns the content of the text widget" do
      expect(subject.ignore_case).to eq(true)
    end
  end
end
