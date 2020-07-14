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

describe Registration::Storage::Config do
  subject { Registration::Storage::Config.instance }
  let(:addon) do
    {
      "arch"         => "x86_64",
      "name"         => "sle-module-legacy",
      "reg_code"     => "",
      "release_type" => "nil",
      "version"      => "12"
    }
  end
  let(:config) do
    {
      "addons"                           => [{
        "arch" => "x86_64", "name" => "sle-module-legacy", "reg_code" => "",
          "release_type" => "nil", "version" => "12"
      }],
      "do_registration"                  => true,
      "email"                            => "foo@example.com",
      "install_updates"                  => false,
      "reg_code"                         => "FOOBAR42",
      "reg_server"                       => "",
      "reg_server_cert"                  => "",
      "reg_server_cert_fingerprint"      => "AB:CD:EF",
      "reg_server_cert_fingerprint_type" => "SHA1",
      "slp_discovery"                    => false
    }
  end

  before do
    # start each test with empty config
    subject.reset
  end

  describe "#reset" do
    it "resets the current configuration" do
      subject.do_registration = true
      subject.reset
      expect(subject.do_registration).to eq(false)
    end
  end

  describe "#export" do
    it "exports only 'do_registration' key when registration is disabled" do
      subject.do_registration = false
      expect(subject.export).to eq("do_registration" => false)
    end

    it "exports complete data as a Hash when registration is enabled" do
      subject.do_registration = true
      subject.reg_server_cert_fingerprint_type = "SHA1"
      subject.reg_server_cert_fingerprint = "AB:CD:EF"
      subject.addons << addon
      subject.email = "foo@example.com"
      subject.reg_code = "FOOBAR42"

      expect(subject.export).to eq(config)
    end

    it "exports imported config unmodified" do
      subject.import(config)
      expect(subject.export).to eq(config)
    end
  end

  describe "#import" do
    it "resets the configuration before importing the data" do
      subject.reg_server = "http://example.com"
      subject.import({})
      expect(subject.reg_server).to eq("")
    end

    it "imports the data from a Hash" do
      subject.import(config)
      expect(subject.do_registration).to eq(true)
      expect(subject.reg_server).to eq("")
      expect(subject.email).to eq("foo@example.com")
      expect(subject.reg_code).to eq("FOOBAR42")
      expect(subject.addons.size).to eq 1
    end
  end
end
