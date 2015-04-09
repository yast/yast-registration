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
      expect(Registration::UrlHelpers).to receive(:registration_url)
    end

    it "registeres the addon from media" do
      expect(Registration::SwMgmt).to receive(:init).and_return(true)
      expect(Yast::Pkg).to receive(:SourceLoad)
      expect(Registration::SwMgmt).to receive(:products_from_repo).with(repo).and_return(products)
      expect(Registration::Registration).to receive(:is_registered?).and_return(true)
      expect_any_instance_of(Registration::RegistrationUI).to receive(:get_available_addons)
        .and_return(remote_addons)
      expect(Registration::SwMgmt).to receive(:select_product_addons).with(products, remote_addons)
      expect(Registration::Addon).to receive(:selected).twice.and_return([remote_addons.first])
      expect(Registration::Addon).to receive(:find_all).and_return(remote_addons)
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
      expect(Registration::SwMgmt).to receive(:init).and_return(true)
      expect(Yast::Pkg).to receive(:SourceLoad)
      expect(Registration::SwMgmt).to receive(:products_from_repo).with(repo).and_return([])
      expect(Yast::Pkg).to receive(:SourceGeneralData).with(repo).and_return({})

      expect(Registration::UI::MediaAddonWorkflow.run(repo)).to eq(:finish)
    end
  end
end
