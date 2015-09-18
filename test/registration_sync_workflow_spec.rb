#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::RegistrationSyncWorkflow do
  describe "#run" do
    before do
      allow(Yast::Pkg).to receive(:SourceFinishAll)
      allow(Yast::Pkg).to receive(:TargetFinish)
      allow(Yast::Pkg).to receive(:TargetInitialize)
      allow(Yast::Pkg).to receive(:TargetLoad)
      allow(Yast::Pkg).to receive(:SourceRestore)
      allow(Registration::UrlHelpers).to receive(:registration_url)
      allow(Registration::SwMgmt).to receive(:get_release_type)
    end

    it "restores repositories, downgrades registration and synchronizes the products" do
      installed_sles = load_yaml_fixture("products_legacy_installation.yml")[1]
      expect(Yast::Update).to receive(:restore_backup)
      expect(Registration::SwMgmt).to receive(:installed_products).and_return([installed_sles])
      expect_any_instance_of(Registration::RegistrationUI).to receive(:downgrade_product)
        .with(installed_sles).and_return([true, nil])
      expect_any_instance_of(Registration::RegistrationUI).to receive(:synchronize_products)
        .with([installed_sles]).and_return(true)
      expect(subject.run).to eq(:next)
    end

    it "returns :abort on an error" do
      msg = "Something failed..."
      expect(subject).to receive(:rollback).and_raise(msg)
      expect(subject.run).to eq(:abort)
    end
  end

  describe ".run" do
    subject { Registration::UI::RegistrationSyncWorkflow }
    it "creates an instance object and calls run()" do
      allow_any_instance_of(subject).to receive(:run).and_return(:next)
      expect(subject.run).to eq(:next)
    end
  end
end
