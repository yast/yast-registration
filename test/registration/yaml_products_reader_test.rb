# Copyright (c) [2022] SUSE LLC
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
require "registration/yaml_products_reader"

describe Registration::YamlProductsReader do
  subject { described_class.new(File.expand_path("#{__dir__}/../fixtures/wsl_products.yml")) }

  describe "#read" do
    it "reads content of yaml file" do
      expect(subject.read.first["name"]).to eq "SLED"
    end

    it "adds arch key if not defined" do
      expect(subject.read.first["arch"]).to eq Yast::Arch.rpm_arch
    end

    it "converts version to version_version" do
      expect(subject.read.first["version_version"]).to eq "15.4"
    end

    it "expands properly arch variable" do
      expect(subject.read.first["register_target"]).to eq "sle-15-#{Yast::Arch.rpm_arch}"
    end

    it "converts default to boolean" do
      products = subject.read
      expect(products[0]["default"]).to eq(false)
      expect(products[1]["default"]).to eq(true)
    end
  end
end
