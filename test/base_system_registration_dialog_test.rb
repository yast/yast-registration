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

      it "registers the base system with provided email and reg. code" do
        expect(Registration::SwMgmt).to receive(:find_base_product).and_return(
          Registration::SwMgmt::FAKE_BASE_PRODUCT)

        # stub the user interaction in the dialog
        expect(Yast::UI).to receive(:UserInput).and_return(:next)
        expect(Yast::UI).to receive(:QueryWidget).with(:email, :Value).and_return(email)
        expect(Yast::UI).to receive(:QueryWidget).with(:reg_code, :Value).and_return(reg_code)

        options = Registration::Storage::InstallationOptions.instance
        expect(options).to receive(:email=).with(email)
        expect(options).to receive(:email).and_return(email)
        expect(options).to receive(:reg_code=).with(reg_code)
        expect(options).to receive(:reg_code).and_return(reg_code)

        expect_any_instance_of(Registration::RegistrationUI).to receive(
          :register_system_and_base_product).and_return([true, nil])

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
