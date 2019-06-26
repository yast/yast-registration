#! /usr/bin/env rspec
# typed: false

require_relative "spec_helper"

describe Registration::UI::RegistrationSyncWorkflow do
  describe "#run_sequence" do
    let(:registration) { Registration::Registration.new }
    let(:registration_ui) { Registration::RegistrationUI.new(registration) }
    let(:products) { load_yaml_fixture("products_legacy_installation.yml") }
    let(:activated_products) { load_yaml_fixture("activated_products.yml") }
    let(:sles) { products[1] }
    let(:legacy) { products[0] }
    let(:activated_sles) { activated_products[2] }
    let(:activated_legacy) { activated_products[2][:extensions][2] }

    before do
      allow(Yast::Pkg).to receive(:SourceFinishAll)
      allow(Yast::Pkg).to receive(:TargetFinish)
      allow(Yast::Pkg).to receive(:TargetInitialize)
      allow(Yast::Pkg).to receive(:TargetLoad)
      allow(Yast::Pkg).to receive(:SourceRestore)
      allow(Yast::Update).to receive(:restore_backup)
      allow(Registration::UrlHelpers).to receive(:registration_url)
      allow(Registration::SwMgmt).to receive(:get_release_type)
      allow(subject).to receive(:registration_ui).and_return(registration_ui)
      allow(subject).to receive(:registration).and_return(registration)
      allow(Registration::Releasever).to receive(:set?).and_return(false)
      allow(Registration::SwMgmt).to receive(:installed_products).and_return([])
    end

    it "restores repositories, downgrades registration and synchronizes the products" do
      expect(Yast::Update).to receive(:restore_backup)
      expect(Registration::SwMgmt).to receive(:installed_products).and_return([sles])
      expect(registration).to receive(:activated_products).and_return([activated_sles])

      expect(registration_ui).to receive(:registered_addons_to_rollback).and_return([])
      expect(registration_ui).to receive(:downgrade_product)
        .with(sles).and_return([true, nil])
      expect(registration_ui).to receive(:synchronize_products)
        .with([sles]).and_return(true)

      expect(subject.run_sequence).to eq(:next)
    end

    it "downgrades the base product first" do
      installed_products = [legacy, sles]
      expect(Registration::SwMgmt).to receive(:installed_products).and_return(installed_products)
      expect(registration).to receive(:activated_products)
        .and_return([activated_legacy, activated_sles])

      expect(registration_ui).to receive(:registered_addons_to_rollback).and_return([])
      # set the expected downgrade order
      expect(registration_ui).to receive(:downgrade_product)
        .with(sles).ordered.and_return([true, nil])
      expect(registration_ui).to receive(:downgrade_product)
        .with(legacy).ordered.and_return([true, nil])

      expect(registration_ui).to receive(:synchronize_products)
        .with(installed_products).and_return(true)
      expect(subject.run_sequence).to eq(:next)
    end

    it "resets the $releasever if it has been set" do
      allow(registration_ui).to receive(:synchronize_products).and_return(true)
      expect(registration).to receive(:activated_products).and_return([activated_sles])
      expect(Registration::Releasever).to receive(:set?).and_return(true)

      expect(registration_ui).to receive(:registered_addons_to_rollback).and_return([])
      releasever = Registration::Releasever.new(nil)
      expect(Registration::Releasever).to receive(:new).with(nil).and_return(releasever)
      expect(releasever).to receive(:activate)

      expect(subject.run_sequence).to eq(:next)
    end
  end
end
