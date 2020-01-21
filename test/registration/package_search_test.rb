# Copyright (c) [2019] SUSE LLC
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

require_relative "../spec_helper"
require "registration/package_search"

describe Registration::PackageSearch do
  subject(:search) { described_class.new(text: text) }

  let(:text) { "connect" }

  let(:pkg1) do
    {
      "id"       => 19418603,
      "name"     => "container-suseconnect",
      "arch"     => "x86_64",
      "version"  => "2.1.0",
      "release"  => "4.6.1",
      "products" => [
        {
          "id"           => 1963,
          "name"         => "Containers Module",
          "identifier"   => "sle-module-containers/15.2/x86_64",
          "type"         => "module",
          "free"         => true,
          "edition"      => "15 SP2",
          "architecture" => "x86_64"
        }
      ]
    }
  end

  let(:pkg2) do
    {
      "id"       => 19756638,
      "name"     => "SUSEConnect",
      "arch"     => "x86_64",
      "version"  => "0.3.23",
      "release"  => "1.6",
      "products" => [
        {
          "id"           => 1946,
          "name"         => "Basesystem Module",
          "identifier"   => "sle-module-basesystem/15.2/x86_64",
          "type"         => "module",
          "free"         => true,
          "edition"      => "15 SP2",
          "architecture" => "x86_64"
        }
      ]
    }
  end

  let(:basesystem) { instance_double(Registration::Addon) }
  let(:base_product) do
    Y2Packager::Product.new(
      name: "SLES", display_name: "SUSE Linux Enterprise 15 SP2", version: "15.2-0",
      arch: :x86_64, category: :base
    )
  end

  describe "#results" do
    let(:packages) { [pkg1, pkg2] }

    before do
      allow(Y2Packager::Product).to receive(:installed_base_product)
        .and_return(base_product)
      allow(SUSE::Connect::PackageSearch).to receive(:search)
        .with(text, product: SUSE::Connect::Zypper::Product).and_return(packages)
      allow(Registration::Addon).to receive(:find_by_id)
        .with(1946).and_return(basesystem)
      allow(Registration::Addon).to receive(:find_by_id)
        .with(1963).and_return(nil)
    end

    it "returns packages from SCC containing the given text in their names" do
      expect(subject.packages).to contain_exactly(
        an_object_having_attributes(
          name:    "container-suseconnect",
          version: "2.1.0",
          release: "4.6.1",
          arch:    "x86_64",
          addon:   nil
        ),
        an_object_having_attributes(
          name:    "SUSEConnect",
          version: "0.3.23",
          release: "1.6",
          arch:    "x86_64",
          addon:   basesystem
        )
      )
    end

    it "limits the search to the given product" do
      expect(SUSE::Connect::PackageSearch).to receive(:search) do |_name, product:|
        expect(product.to_triplet).to eq("SLES/15.2/x86_64")
        packages
      end
      subject.packages
    end

    context "when the search is case sensitive" do
      subject(:search) { described_class.new(text: text, ignore_case: false) }

      let(:text) { "Connect" }

      it "filters out package which do not match" do
        expect(subject.packages).to contain_exactly(
          an_object_having_attributes(
            name:    "SUSEConnect",
            version: "0.3.23",
            release: "1.6",
            arch:    "x86_64",
            addon:   basesystem
          )
        )
      end
    end
  end
end
