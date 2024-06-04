#!/usr/bin/env rspec
# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require_relative "../../spec_helper"
require "registration/ui/autoyast_addon_dialog"

describe Registration::UI::AutoyastAddonDialog do
  subject(:dialog) { described_class.new(addons) }

  let(:addons) { [addon] }

  let(:addon) do
    {
      "name"         => "free_cool_in_addon",
      "version"      => "666",
      "arch"         => "s390x",
      "release_type" => nil,
      "reg_code"     => "hell_driven_delevopment"
    }
  end

  describe "#run" do
    before do
      allow(Yast::UI).to receive(:UserInput).and_return(:next)
    end

    it "does not crash" do
      expect { dialog.run }.to_not raise_error
    end
  end
end
