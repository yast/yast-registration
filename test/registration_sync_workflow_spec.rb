#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::RegistrationSyncWorkflow do
  describe "#run_sequence" do
    let(:registration_ui) { Registration::RegistrationUI.new(nil) }
    let(:products) { load_yaml_fixture("products_legacy_installation.yml") }
    let(:sles) { products[1] }
    let(:legacy) { products[0] }

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
      allow(Registration::Releasever).to receive(:set?).and_return(false)
      allow(Registration::SwMgmt).to receive(:installed_products).and_return([])
    end

    it "restores repositories, downgrades registration and synchronizes the products" do
      expect(Yast::Update).to receive(:restore_backup)
      expect(Registration::SwMgmt).to receive(:installed_products).and_return([sles])

      expect(registration_ui).to receive(:downgrade_product)
        .with(sles).and_return([true, nil])
      expect(registration_ui).to receive(:synchronize_products)
        .with([sles]).and_return(true)

      expect(subject.run_sequence).to eq(:next)
    end

    it "downgrades the base product first" do
      installed_products = [legacy, sles]
      expect(Registration::SwMgmt).to receive(:installed_products).and_return(installed_products)

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
      expect(Registration::Releasever).to receive(:set?).and_return(true)

      releasever = Registration::Releasever.new(nil)
      expect(Registration::Releasever).to receive(:new).with(nil).and_return(releasever)
      expect(releasever).to receive(:activate)

      expect(subject.run_sequence).to eq(:next)
    end
  end
end
