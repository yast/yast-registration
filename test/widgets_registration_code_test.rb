#!/usr/bin/env rspec

require_relative "spec_helper"
require "registration/widgets/registration_code"

describe Registration::Widgets::RegistrationCode do
  let(:options) { Registration::Storage::InstallationOptions.instance }
  let(:base_product) { Registration::SwMgmt::FAKE_BASE_PRODUCT }

  before do
    allow(options).to receive(:reg_code).and_return("")
    allow(options).to receive(:custom_url).and_return(nil)
    allow(subject).to receive(:boot_url).and_return(nil)
  end

  it "has help text" do
    expect(subject.help).to_not be_empty
  end

  context "initialization" do
    context "when a previous registration code exists" do
      it "initializes the widget with it" do
        allow(options).to receive(:reg_code).and_return("previous_code")
        expect(subject).to receive(:value=).with("previous_code")

        subject.init
      end
    end

    context "when no previous registration code exists" do
      it "initializes the widget with custom url if exists" do
        allow(options).to receive(:reg_code).and_return("")
        allow(options).to receive(:custom_url).and_return("http://smt.example.com")

        expect(subject).to receive(:value=).with("http://smt.example.com")

        subject.init
      end

      it "initializes the widget with the cmdline boot url if no custom url" do
        allow(options).to receive(:reg_code).and_return("")
        allow(options).to receive(:custom_url).and_return(nil)
        allow(subject).to receive(:boot_url).and_return("http://boot.example.de")
        expect(subject).to receive(:value=).with("http://boot.example.de")

        subject.init
      end
    end
  end

  context "validation" do
    it "reports an error in case of a url but not valid one" do
      allow(subject).to receive(:value).and_return("ftp://smt.example.com")
      expect(subject).to receive(:error).and_return(false)

      expect(subject.validate).to eq false
    end
  end

  context "store" do
    context "when the value is empty or not an URL" do
      before do
        allow(subject).to receive(:valid_url?).and_return(false)
        allow(options).to receive(:custom_url=)
        allow(options).to receive(:reg_code=)
        allow(subject).to receive(:register)
        allow(subject).to receive(:default_url).and_return("default_url")
      end

      it "stores the current value" do
        allow(subject).to receive(:value).and_return(nil)
        expect(options).to receive(:reg_code=).with(nil)

        subject.store
      end

      it "stores as the custom url the default one" do
        allow(subject).to receive(:value).and_return("871263")
        expect(options).to receive(:reg_code=).with("871263")
        expect(options).to receive(:custom_url=).with("default_url")

        subject.store
      end

      it "tries to register to the default url" do
        expect(subject).to receive(:register)

        subject.store
      end
    end

    context "when the value is a valid URL" do
      it "stores the custom url and an empty registration code" do
        valid_url = "http://smt.example.com"
        allow(subject).to receive(:register)
        allow(subject).to receive(:value).and_return(valid_url)
        expect(options).to receive(:reg_code=).with("")
        expect(options).to receive(:custom_url=).with(valid_url)

        subject.store
      end

      it "tries to register to the given URL" do
        expect(subject).to receive(:register)

        subject.store
      end
    end
  end

  describe "#register" do
    before do
      allow(subject).to receive(:skip?).and_return(false)
      allow(Registration::Registration).to receive(:is_registered?).and_return(false)
      allow(Registration::SwMgmt).to receive(:find_base_product).and_return(base_product)
    end

    it "skips registration if empty and returns false" do
      allow(subject).to receive(:skip?).and_call_original
      expect(subject).to receive(:value).and_return("")
      expect(Registration::Registration).not_to receive(:is_registered?)

      expect(subject.register).to eq false
    end

    it "skips registration if already registered and returns false" do
      expect(Registration::Registration).to receive(:is_registered?).and_return(true)
      expect(subject).not_to receive(:register_system_and_base_product)

      expect(subject.register).to eq false
    end

    it "skips registration if not base product, reports and error and returns false" do
      expect(Registration::Registration).to receive(:is_registered?).and_return(false)
      expect(Registration::SwMgmt).to receive(:find_base_product).and_return(nil)
      expect(Registration::Helpers).to receive(:report_no_base_product)
      expect(subject).not_to receive(:register_system_and_base_product)

      expect(subject.register).to eq false
    end

    it "returns false if registration fails" do
      expect(subject).to receive(:register_system_and_base_product).and_return(false)

      expect(subject.register).to eq false
    end

    it "saves the state of the system registration if success and returns true" do
      expect(subject).to receive(:register_system_and_base_product).and_return(true)
      expect(options).to receive(:base_registered=).with(true)

      expect(subject.register).to eq true
    end
  end
end
