#! /usr/bin/env rspec

require_relative "spec_helper"
require "yaml"

describe "Registration::UI::MediaAddonWorkflow" do
  describe ".run" do
    let(:repo) { 42 }
    # sle-module-legacy product
    let(:products) { [YAML.load_file(fixtures_file("products_legacy_installation.yml")).first] }
    let(:remote_addons) { YAML.load_file(fixtures_file("available_addons.yml")) }

    before do
      allow(Registration::UrlHelpers).to receive(:registration_url)
      allow(Registration::SwMgmt).to receive(:init).and_return(true)
      allow(Yast::Pkg).to receive(:SourceLoad)
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(repo).and_return({})
      allow(Registration::SwMgmt).to receive(:products_from_repo).with(repo).and_return(products)
      allow(Registration::SwMgmt).to receive(:select_product_addons).with(products, remote_addons)
      allow(Registration::Addon).to receive(:selected).twice.and_return([remote_addons.first])
      allow_any_instance_of(Registration::RegistrationUI).to receive(:get_available_addons)
        .and_return(remote_addons)
      allow(Registration::Addon).to receive(:find_all).and_return(remote_addons)
    end

    it "registers the addon from media" do
      expect(Registration::Registration).to receive(:is_registered?).and_return(true)
      expect_any_instance_of(Registration::RegistrationUI).to receive(:register_addons)
        .and_return(:next)

      expect(Registration::UI::MediaAddonWorkflow.run(repo)).to eq(:next)
    end

    it "aborts when package management initialization fails" do
      expect(Registration::SwMgmt).to receive(:init).and_return(false)
      expect(Yast::Report).to receive(:Error)

      expect(Registration::UI::MediaAddonWorkflow.run(repo)).to eq(:abort)
    end

    it "skips registation when the media addon does not provide any product" do
      expect(Registration::SwMgmt).to receive(:products_from_repo).with(repo).and_return([])
      expect(Registration::UI::MediaAddonWorkflow.run(repo)).to eq(:finish)
    end

    it "registers the base system if it is not registered yet" do
      # the base system registration skipped then registered (to cover more paths)
      expect(Registration::Registration).to receive(:is_registered?).exactly(3).times
        .and_return(false, false, true)
      allow_any_instance_of(Registration::UI::BaseSystemRegistrationDialog).to receive(
        :run).and_return(:skip, :next)
      expect(Yast::Popup).to receive(:YesNo).and_return(false)

      expect_any_instance_of(Registration::RegistrationUI).to receive(:register_addons)
        .and_return(:next)

      expect(Registration::UI::MediaAddonWorkflow.run(repo)).to eq(:next)
    end

    it "skips addon product registration if base product registration is skipped" do
      # skip base system registration
      expect(Registration::Registration).to receive(:is_registered?).twice.times
        .and_return(false)
      expect_any_instance_of(Registration::UI::BaseSystemRegistrationDialog).to receive(
        :run).and_return(:skip)
      expect(Yast::Popup).to receive(:YesNo).and_return(true)

      # no addon is registered
      expect_any_instance_of(Registration::RegistrationUI).to_not receive(:register_addons)

      expect(Registration::UI::MediaAddonWorkflow.run(repo)).to eq(:skip)
    end
  end
end
