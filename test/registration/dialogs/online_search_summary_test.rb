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
require "registration/dialogs/online_search_summary"
require "registration/addon"
require "registration/remote_package"
require "cwm/rspec"

describe Registration::Dialogs::OnlineSearchSummary do
  subject { described_class.new([package], [addon]) }

  include_examples "CWM::Dialog"

  let(:addon) { instance_double(Registration::Addon, name: "addon1") }
  let(:package) { instance_double(Registration::RemotePackage, name: "pkg1") }

  describe "#contents" do
    it "includes a list of addons" do
      expect(subject.contents.to_s).to include("Modules/extensions to register (1)")
    end

    it "includes a list of packages" do
      expect(subject.contents.to_s).to include("Selected packages (1)")
    end

    context "when the list of addons is empty" do
      subject { described_class.new([package], []) }

      it "does not include a list of addons" do
        expect(subject.contents.to_s).to_not include("Modules")
      end
    end
  end
end
