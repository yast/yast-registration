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
require "registration/widgets/remote_package_details"
require "registration/package_search"
require "registration/remote_package"
require "cwm/rspec"

describe Registration::Widgets::RemotePackageDetails do
  include_examples "CWM::RichText"

  describe "#update" do
    let(:package) do
      instance_double(
        Registration::RemotePackage,
        name: "yast2", full_version: "4.2.49-1.1", arch: "x86_64", addon: addon
      )
    end

    let(:addon) do
      instance_double(
        Registration::Addon, name: "Basesystem Module", registered?: true
      )
    end

    it "displays the result details" do
      expect(subject).to receive(:value=)
        .with("<b>Name:</b> yast2<br>" \
              "<b>Version:</b> 4.2.49-1.1<br>" \
              "<b>Architecture:</b> x86_64<br>" \
              "<b>Product:</b> Basesystem Module (registered)")
      subject.update(package)
    end
  end
end
