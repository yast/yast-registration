#! /usr/bin/env rspec

require_relative "../../spec_helper"
require "y2packager/control_product_spec"
require "registration/clients/scc_auto"

describe Registration::Clients::SCCAuto do
  let(:config) { ::Registration::Storage::Config.instance }

  before do
    allow(Yast::Report).to receive(:Error)
  end

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
    let(:config) do
      instance_double(Registration::Storage::Config)
    end

    let(:product) do
      instance_double(Y2Packager::Product, short_name: "SLES15-SP4")
    end

    before do
      allow(Yast::AutoinstFunctions).to receive(:selected_product).and_return(product)
      allow(Registration::Storage::Config).to receive(:instance).and_return(config)
    end

    it "imports given hash" do
      settings = { "reg_code" => "SOME-CODE" }
      expect(config).to receive(:import).with(settings)
      subject.import(settings)
    end

    context "when the registration code is not specified" do
      let(:loader) do
        instance_double(Registration::Storage::RegCodes, reg_codes: reg_codes)
      end

      let(:reg_codes) do
        { "SLES15-SP4" => "INTERNAL-USE-ONLY" }
      end

      before do
        allow(Registration::Storage::RegCodes).to receive(:instance).and_return(loader)
      end

      it "reads the code from the registration codes loader" do
        imported = { "reg_code" => "INTERNAL-USE-ONLY" }
        expect(config).to receive(:import).with(imported)
        subject.import({})
      end

      context "but respositories are not initialized yet" do
        let(:product) { instance_double(Y2Packager::ControlProductSpec) }

        it "does not read the code from the registration codes loader" do
          expect(config).to receive(:import).with({})
          subject.import({})
        end
      end

      context "but the selected product is unknown" do
        let(:product) { nil }

        it "does not read the code from the registration codes loader" do
          expect(config).to receive(:import).with({})
          subject.import({})
        end
      end
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
      allow(Y2Packager::ProductSpec).to receive(:base_products).and_return([])
      # clean cache
      ::Registration::Storage::Cache.instance.addon_services = []
      allow(Registration::UrlHelpers).to receive(:slp_discovery_feedback).and_return([])
      allow(::Registration::SwMgmt).to receive(:init)
    end

    it "just returns true if config is not set to register and mode is not update" do
      config.do_registration = false
      allow(Yast::Mode).to receive(:update).and_return(false)

      expect(subject.write).to eq true
    end

    it "initializes software managent in normal mode" do
      config.do_registration = true
      allow(subject).to receive(:register_addons) # do not test addons here. It is done below
      allow(Yast::Mode).to receive(:normal).and_return(true)
      expect(::Registration::SwMgmt).to receive(:init)

      allow(subject).to receive(:registration_ui).and_return(
        double(register_system_and_base_product: true, disable_update_repos: true)
      )

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
