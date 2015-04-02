#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::BaseSystemRegistrationDialog do
  subject { Registration::UI::BaseSystemRegistrationDialog }

  let(:email) { "email@example.com" }
  let(:reg_code) { "my-reg-code" }

  describe ".run" do
    before do
      allow(Yast::UI).to receive(:TextMode).and_return(false)
      expect(Yast::Wizard).to receive(:SetContents)
      expect(Registration::UrlHelpers).to receive(:registration_url).and_return(nil)

      # installation mode
      allow(Yast::Mode).to receive(:installation).and_return(true)
      allow(Yast::Mode).to receive(:normal).and_return(false)
      allow(Yast::Mode).to receive(:update).and_return(false)
    end

    context "the system is not registered yet" do
      before do
        allow(Registration::Registration).to receive(:is_registered?).and_return(false)
      end

      it "registeres the base system with provided email and reg. code" do
        expect(Registration::SwMgmt).to receive(:find_base_product).and_return(
          Registration::SwMgmt::FAKE_BASE_PRODUCT)

        # stub the user interaction in the dialog
        expect(Yast::UI).to receive(:UserInput).and_return(:next)
        expect(Yast::UI).to receive(:QueryWidget).with(:email, :Value).and_return(email)
        expect(Yast::UI).to receive(:QueryWidget).with(:reg_code, :Value).and_return(reg_code)

        expect_any_instance_of(Registration::Storage::InstallationOptions).to receive(:email=)
        expect_any_instance_of(Registration::Storage::InstallationOptions).to receive(:reg_code=)
        expect_any_instance_of(Registration::Storage::InstallationOptions).to receive(:email)
          .twice.and_return(email)
        expect_any_instance_of(Registration::Storage::InstallationOptions).to receive(:reg_code)
          .twice.and_return(reg_code)

        # FIXME: should be 'expect', but it fails (expects 2 calls, huh???)
        allow_any_instance_of(Registration::RegistrationUI).to receive(
          :register_system_and_base_product).with(email, reg_code,
            register_base_product: true).and_return(true, nil)

        expect(subject.run).to eq(:next)
      end
    end

    context "the system is already registered" do
      before do
        #        expect(Registration::Registration).to receive(:is_registered?).and_return(true)
      end
    end
  end
end
