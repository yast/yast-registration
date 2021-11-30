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

      expect(subject.export).to include(
        "do_registration" => true,
        "email"           => "foo@example.com",
        "reg_code"        => "FOOBAR42"
      )
    end

    context "when the email is nil" do
      before do
        subject.do_registration = true
        subject.email = nil
      end

      it "does not include the email" do
        expect(subject.export.keys).to_not include("email")
      end
    end

    context "when the reg_server is nil" do
      before do
        subject.do_registration = true
        subject.reg_server = nil
      end

      it "does not include the reg_server" do
        expect(subject.export.keys).to_not include("reg_server")
      end
    end

    context "when the reg_code is nil" do
      before do
        subject.do_registration = true
        subject.reg_code = nil
      end

      it "does not include the reg_code" do
        expect(subject.export.keys).to_not include("reg_code")
      end
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

  describe "#read" do
    before do
      subject.reset
      allow(::Registration::Registration).to receive(:is_registered?).and_return(registered)
    end

    let(:registered) { true }

    let(:activations) do
      [basesystem_activation, sles_activation, workstation_activation]
    end

    let(:config) do
      SUSE::Connect::Config.new(fixtures_file("SUSEConnect"))
    end

    let(:status) do
      instance_double(
        SUSE::Connect::Status,
        activations:        activations,
        activated_products: [sles_product, basesystem_product, workstation_product]
      )
    end

    let(:sles_activation) do
      OpenStruct.new(
        "regcode" => "0123456789",
        "service" => OpenStruct.new(
          "product" => OpenStruct.new(
            "name" => "SUSE Linux Enteprise Server", "identifier" => "SLES", "isbase" => true
          )
        )
      )
    end

    let(:basesystem_activation) do
      OpenStruct.new(
        "service" => OpenStruct.new(
          "product" => OpenStruct.new(
            "name" => "Basesystem Module", "identifier" => "sle-basesystem"
          )
        )
      )
    end

    let(:workstation_activation) do
      OpenStruct.new(
        "regcode" => "ABCDEFGHIJ",
        "service" => OpenStruct.new(
          "product" => OpenStruct.new(
            "name" => "Workstation Extension", "identifier" => "sle-we"
          )
        )
      )
    end

    let(:sles_product) { sles_activation.service.product }
    let(:basesystem_product) { basesystem_activation.service.product }
    let(:workstation_product) { workstation_activation.service.product }

    before do
      allow(SUSE::Connect::Status).to receive(:new).and_return(status)
      allow(SUSE::Connect::Config).to receive(:new).and_return(config)
    end

    it "reads the registration information" do
      subject.read
      expect(subject.reg_server).to eq(config.url)
      expect(subject.email).to eq(config.email)
    end

    it "includes the addons but not the base product" do
      subject.read
      expect(subject.addons).to contain_exactly(
        a_hash_including("name" => "sle-basesystem"),
        a_hash_including("name" => "sle-we", "reg_code" => "ABCDEFGHIJ")
      )
    end

    it "sets the configuration as modified" do
      expect { subject.read }.to change { subject.modified }.from(false).to(true)
    end

    context "when the system is not registered" do
      let(:registered) { false }

      it "does not read the registration information" do
        subject.read
        expect(subject.reg_server).to be_empty
        expect(subject.email).to be_empty
      end
    end
  end
end
