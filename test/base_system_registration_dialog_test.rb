#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::BaseSystemRegistrationDialog do
  include Yast::UIShortcuts

  let(:email) { "email@example.com" }
  let(:reg_code) { "my-reg-code" }
  let(:custom_url) { "http://smt.example.com/" }

  describe ".run" do
    let(:instance) { double("dialog") }

    it "runs the dialog" do
      dialog_instance = double("dialog")
      expect(described_class).to receive(:new).and_return(dialog_instance)
      expect(dialog_instance).to receive(:run).and_return(:next)
      expect(described_class.run).to eq(:next)
    end
  end

  describe "#run" do
    let(:base_product) { Registration::SwMgmt::FAKE_BASE_PRODUCT }
    let(:mode) { "installation" }

    before do
      allow(Registration::SwMgmt).to receive(:find_base_product).and_return(base_product)
      allow(Yast::Mode).to receive(:mode).and_return(mode)
      allow(Registration::Registration).to receive(:is_registered?).and_return(registered?)
    end

    context "when system is not registered" do
      let(:registered?) { false }
      let(:registration_ui) { double("registration_ui") }

      before do
        allow(Registration::UrlHelpers).to receive(:registration_url).and_return(nil)
        allow(Registration::RegistrationUI).to receive(:new).and_return(registration_ui)
      end

      context "when user enters a correct regcode" do
        it "registers the base system with provided email and reg. code" do
          expect(Yast::UI).to receive(:QueryWidget).with(:email, :Value)
            .and_return(email)
          expect(Yast::UI).to receive(:QueryWidget).with(:reg_code, :Value)
            .and_return(reg_code)
          expect(Yast::UI).to receive(:UserInput).and_return(:next)

          options = Registration::Storage::InstallationOptions.instance
          # Avoid modifying the singleton object
          expect(options).to receive(:email=).with(email)
          expect(options).to receive(:email).and_return(email)
          expect(options).to receive(:reg_code=).with(reg_code)
          expect(options).to receive(:reg_code).and_return(reg_code)

          expect(registration_ui).to receive(:register_system_and_base_product)
            .and_return([true, nil])

          expect(subject.run).to eq(:next)
        end
      end

      context "when user enters a wrong regcode" do
        it "does not register the system" do
          expect(Yast::UI).to receive(:QueryWidget).with(:email, :Value)
            .and_return(email)
          expect(Yast::UI).to receive(:QueryWidget).with(:reg_code, :Value)
            .and_return(reg_code)
          expect(Yast::UI).to receive(:UserInput).and_return(:next, :abort)
          expect(Registration::UI::AbortConfirmation).to receive(:run).and_return(true)

          expect(registration_ui).to receive(:register_system_and_base_product)
            .and_return([false, nil])

          expect(subject.run).to eq(:abort)
        end
      end

      context "when user enters a local SMT server" do
        it "registers the system via local SMT server" do
          expect(Yast::UI).to receive(:QueryWidget).with(:custom_url, :Value)
            .and_return(custom_url)
          expect(Yast::UI).to receive(:UserInput).and_return(:register_local, :next)

          options = Registration::Storage::InstallationOptions.instance
          # Avoid modifying the singleton object
          expect(options).to receive(:custom_url=).with(custom_url)
          expect(options).to receive(:custom_url).and_return(custom_url)
          expect(options).to receive(:reg_code=).with("")
          expect(options).to receive(:email=).with("")

          expect(registration_ui).to receive(:register_system_and_base_product)
            .and_return([true, nil])

          expect(subject.run).to eq(:next)
        end
      end

      context "when user skips registration" do
        it "does not try to register the system and close the dialog" do
          allow(Yast::UI).to receive(:UserInput).and_return(:skip_registration, :next)
          expect(Yast::Popup).to receive(:YesNo).with(/Really skip/)
            .and_return(true)
          expect(subject.run).to eq(:skip)
        end
      end
    end

    context "when system is already registered"  do
      let(:registered?) { true }

      context "in installation mode" do
        it "disables widgets" do
          expect(Yast::UI).to receive(:ChangeWidget).with(Id(:action), :Enabled, false)
          allow(Yast::UI).to receive(:ChangeWidget).and_call_original
          allow(subject).to receive(:event_loop).and_return(nil)
          subject.run
        end
      end

      context "in normal mode" do
        let(:mode) { "normal" }

        it "shows the re-register extensions button" do
          allow(subject).to receive(:PushButton).and_call_original
          expect(subject).to receive(:PushButton)
            .with(Id(:reregister_addons), _("&Register Extensions or Modules Again"))
          allow(subject).to receive(:event_loop).and_return(nil)
          subject.run
        end
      end
    end
  end
end
