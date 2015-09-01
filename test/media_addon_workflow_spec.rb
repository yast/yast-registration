#! /usr/bin/env rspec

require_relative "spec_helper"
require "yaml"

describe "Registration::UI::MediaAddonWorkflow" do
  describe ".run" do
    subject(:run) { Registration::UI::MediaAddonWorkflow.run(repo) }

    let(:repo) { 42 }
    # sle-module-legacy product
    let(:legacy_module_products) do
      [load_yaml_fixture("products_legacy_installation.yml").first]
    end
    let(:remote_addons) { load_yaml_fixture("available_addons.yml") }
    let(:products_from_repo) { legacy_module_products }

    before do
      # SwMgmt initialization
      allow(Registration::SwMgmt).to receive(:init).and_return swmgmt_init
      # List of products
      allow(Registration::SwMgmt).to receive(:products_from_repo)
        .and_return(products_from_repo)
    end

    context "if package management initialization fails" do
      let(:swmgmt_init) { false }

      it "aborts" do
        allow(Yast::Pkg).to receive(:LastError)
        expect(Yast::Report).to receive(:Error)
        expect(run).to eq(:abort)
      end
    end

    context "if package management initialization success" do
      let(:swmgmt_init) { true }

      before do
        # Load source information
        allow(Yast::Pkg).to receive(:SourceLoad)
        # Information about the source for displaying it
        allow(Yast::Pkg).to receive(:SourceGeneralData).and_return({})
        # Url of the registration server
        allow(Registration::UrlHelpers).to receive(:registration_url)
      end

      context "and the media addon does not provide any product" do
        let(:products_from_repo) { [] }

        it "skips registration" do
          expect(run).to eq :finish
        end
      end

      context "and the media addon provides a list of products" do
        before do
          # Three calls to mock the selection of addons
          allow(Registration::SwMgmt).to receive(:select_product_addons)
          allow(Registration::Addon).to receive(:find_all).and_return(remote_addons)
          allow(Registration::Addon).to receive(:selected).and_return(remote_addons[0, 1])
          # List of available addons
          allow_any_instance_of(Registration::RegistrationUI).to receive(:get_available_addons)
            .and_return(remote_addons)
        end

        it "registers the base system and the addons" do
          # False before calling the Base registration dialog. True afterwards
          allow(Registration::Registration).to receive(:is_registered?)
            .and_return(false, true, true)

          # Base system is registered
          expect_any_instance_of(Registration::UI::BaseSystemRegistrationDialog)
            .to receive(:run).and_return(:next)
          # Addons are registered
          expect_any_instance_of(Registration::RegistrationUI).to receive(:register_addons)
            .and_return(:next)
          expect(run).to eq(:next)
        end

        it "registers only the addons if base system is already registered" do
          allow(Registration::Registration).to receive(:is_registered?)
            .and_return(true)

          # No base system registration
          expect_any_instance_of(Registration::UI::BaseSystemRegistrationDialog)
            .to_not receive(:run)
          # Registration of addons
          expect_any_instance_of(Registration::RegistrationUI).to receive(:register_addons)
            .and_return(:next)
          expect(run).to eq :next
        end

        it "skips addons registration if base system registration is skipped" do
          # skip base system registration
          allow(Registration::Registration).to receive(:is_registered?).and_return(false)
          allow(Yast::Popup).to receive(:YesNo).and_return(true)

          # Skipped attempt to register base system
          expect_any_instance_of(Registration::UI::BaseSystemRegistrationDialog)
            .to receive(:run).and_return(:skip)
          # no addon is registered
          expect_any_instance_of(Registration::RegistrationUI).to_not receive(:register_addons)
          expect(run).to eq(:skip)
        end
      end
    end
  end
end
