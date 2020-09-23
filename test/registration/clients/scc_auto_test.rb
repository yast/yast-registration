#! /usr/bin/env rspec

require_relative "../../spec_helper"

# we have enabled strict method checking in rspec, so we need to define profile method
# by opening class. Profile is stubbed, so it is just fake class

module Yast
  class Profile
    def self.current
      {}
    end
  end
end

describe Registration::Clients::SCCAuto do
  let(:config) { ::Registration::Storage::Config.instance }

  describe "#summary" do
    it "returns string with config description" do
      expect(subject.summary).to be_a(::String)
    end
  end

  describe "#reset" do
    it "resets config to initial state" do
      expect(config).to receive(:reset)

      subject.reset
    end
  end

  describe "#change" do
    it "runs registration workflow" do
      expect(::Registration::UI::AutoyastConfigWorkflow).to receive(:run)

      subject.change
    end
  end

  describe "#import" do
    it "imports given hash" do
      expect { subject.import({}) }.to_not raise_error
    end
  end

  describe "#export" do
    it "returns hash" do
      expect(subject.export).to be_a(::Hash)
    end
  end

  describe "#read" do
    it "returns true" do
      expect(config).to receive(:read)
      expect(subject.read).to eq true
    end
  end

  describe "#packages" do
    it "returns hash to not install neither remove anything" do
      packages = subject.packages
      expect(packages["install"]).to eq []
      expect(packages["remove"]).to eq []
    end
  end

  describe "#modified" do
    it "sets modified flag in config" do
      config.modified = false
      subject.modified

      expect(config.modified).to eq true
    end
  end

  describe "#modified?" do
    it "returns if modified flag is set in config" do
      config.modified = true
      expect(subject.modified?).to eq true
    end
  end

  describe "#write" do
    before do
      Y2Packager::MediumType.type = :online
      allow(Y2Packager::ProductControlProduct).to receive(:products).and_return("SLES")
    end

    it "just returns true if config is not set to register and mode is not update" do
      config.do_registration = false
      allow(Yast::Mode).to receive(:update).and_return(false)

      expect(subject.write).to eq true
    end

    it "initializes software managent in normal mode" do
      config.do_registration = true
      allow(Yast::Mode).to receive(:normal).and_return(true)
      expect(::Registration::SwMgmt).to receive(:init)

      subject.write
    end

    it "registers previously registered base system and addons" do
      allow(Yast::Mode).to receive(:update).and_return(false)
      subject.import(
        "do_registration" => true,
        "addons"          => [{
          "name"    => "sle-module-basesystem",
          "version" => "15.2",
          "arch"    => "x86_64"
        }]
      )

      allow(subject).to receive(:registration_ui).and_return(
        double(register_system_and_base_product: true, disable_update_repos: true)
      )

      addon = double.as_null_object
      expect(Registration::AutoyastAddons).to receive(:new).and_return(addon)
      expect(addon).to receive(:register)

      subject.write
    end

    context "in autoupgrade mode" do
      before do
        allow(Yast::Mode).to receive(:update).and_return(true)
      end

      it "runs offline migration workflow if system is registered" do
        expect(::Registration::UI::OfflineMigrationWorkflow).to receive(:new)
          .and_return(double(main: :next))
        allow(subject).to receive(:old_system_registered?).and_return(true)

        subject.write
      end

      it "skips registration and returns true for unregistered system and offline medium" do
        allow(subject).to receive(:old_system_registered?).and_return(false)
        Y2Packager::MediumType.type = :offline

        expect(subject.write).to eq true
      end

      it "reports error and return false for unregistered system and online medium" do
        allow(subject).to receive(:old_system_registered?).and_return(false)
        Y2Packager::MediumType.type = :online

        expect(Yast::Popup).to receive(:Error)

        expect(subject.write).to eq false
      end
    end
  end
end
