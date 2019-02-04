#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::BaseSystemRegistrationDialog do
  include Yast::UIShortcuts

  let(:email) { "email@example.com" }
  let(:reg_code) { "my-reg-code" }
  let(:custom_url) { "http://smt.example.com/" }
  let(:default_url) { SUSE::Connect::Config.new.url }

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
      textdomain "registration"

      allow(Registration::SwMgmt).to receive(:find_base_product).and_return(base_product)
      allow(Yast::Mode).to receive(:mode).and_return(mode)
      allow(Registration::Registration).to receive(:is_registered?).and_return(registered?)
      allow(Registration::UrlHelpers).to receive(:slp_discovery_feedback).and_return([])
      allow(Yast::UI).to receive(:ChangeWidget)
    end

    context "when system is not registered" do
      let(:registered?) { false }
      let(:registration_ui) { double("registration_ui") }

      before do
        allow(Registration::UrlHelpers).to receive(:registration_url).and_return(nil)
        allow(Registration::RegistrationUI).to receive(:new).and_return(registration_ui)
        allow(Registration::Helpers).to receive(:reset_registration_status)
      end

      it "limits the reg_code InputField to 512" do
        allow(subject).to receive(:event_loop).and_return(nil)

        expect(Yast::UI).to receive(:ChangeWidget).with(:reg_code, :InputMaxLength, 512)

        subject.run
      end

      context "when user enters a correct regcode" do
        it "registers the base system with provided email and reg. code" do
          expect(Yast::UI).to receive(:QueryWidget).with(:email, :Value)
            .and_return(email)
          allow(Yast::UI).to receive(:QueryWidget).with(:reg_code, :Value)
            .and_return(reg_code)
          expect(Yast::UI).to receive(:UserInput).and_return(:next)

          options = Registration::Storage::InstallationOptions.instance
          # Avoid modifying the singleton object
          expect(options).to receive(:email=).with(email)
          expect(options).to receive(:email).and_return(email)
          expect(options).to receive(:reg_code=).with(reg_code)
          expect(options).to receive(:reg_code).and_return(reg_code)
          expect(options).to receive(:custom_url=).with(default_url)
          expect(options).to receive(:custom_url).and_return(default_url)

          expect(registration_ui).to receive(:register_system_and_base_product)
            .and_return([true, nil])

          expect(subject.run).to eq(:next)
        end
      end

      context "when user enters a wrong regcode" do
        it "does not register the system" do
          expect(Yast::UI).to receive(:QueryWidget).with(:email, :Value)
            .and_return(email)
          allow(Yast::UI).to receive(:QueryWidget).with(:reg_code, :Value)
            .and_return(reg_code)
          expect(Yast::UI).to receive(:UserInput).and_return(:next, :abort)
          expect(Registration::UI::AbortConfirmation).to receive(:run).and_return(true)

          options = Registration::Storage::InstallationOptions.instance
          # Avoid modifying the singleton object
          expect(options).to receive(:email=).with(email)
          expect(options).to receive(:reg_code=).with(reg_code)
          expect(options).to receive(:custom_url=).with(default_url)

          expect(registration_ui).to receive(:register_system_and_base_product)
            .and_return([false, nil])

          expect(subject.run).to eq(:abort)
        end
      end

      context "when user enters an invalid regcode" do
        # include CRLF characters which are not allowed
        let(:reg_code) { "\nmy-reg-code\r" }
        it "displays error popup and does not register the system" do
          allow(Yast::UI).to receive(:QueryWidget).with(:reg_code, :Value)
            .and_return(reg_code)
          allow(Yast::UI).to receive(:UserInput).and_return(:next, :abort)
          allow(Registration::UI::AbortConfirmation).to receive(:run).and_return(true)

          expect(Yast::Report).to receive(:Error).with(/Invalid registration code/)
          expect(registration_ui).to_not receive(:register_system_and_base_product)

          subject.run
        end
      end

      context "when user sets a registration URL through regurl= parameter" do
        let(:regurl) { "https://example.suse.net" }

        before do
          allow(Registration::UrlHelpers).to receive(:boot_reg_url).and_return(regurl)
        end

        it "uses the given URL to register the system" do
          expect(Yast::UI).to receive(:QueryWidget).with(:email, :Value)
            .and_return(email)
          allow(Yast::UI).to receive(:QueryWidget).with(:reg_code, :Value)
            .and_return(reg_code)
          expect(Yast::UI).to receive(:UserInput).and_return(:next)

          options = Registration::Storage::InstallationOptions.instance
          # Avoid modifying the singleton object
          expect(options).to receive(:email=).with(email)
          expect(options).to receive(:email).and_return(email)
          expect(options).to receive(:reg_code=).with(reg_code)
          expect(options).to receive(:reg_code).and_return(reg_code)
          expect(options).to receive(:custom_url=).with(regurl)
          expect(options).to receive(:custom_url).and_return(regurl)

          expect(registration_ui).to receive(:register_system_and_base_product)
            .and_return([true, nil])

          expect(subject.run).to eq(:next)
        end
      end

      context "when user enters a local SMT server" do
        it "registers the system via local SMT server" do
          allow(Yast::UI).to receive(:QueryWidget).with(:custom_url, :Value)
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

      context "when user enters an invalid local SMT server" do
        it "shows an error and does not try to register the system" do
          allow(Yast::UI).to receive(:QueryWidget).with(:custom_url, :Value)
            .and_return("ftp://smt.suse.com")
          expect(Yast::UI).to receive(:UserInput).and_return(:register_local, :next, :abort)
          expect(Registration::UI::AbortConfirmation).to receive(:run).and_return(true)
          expect(Yast::Report).to receive(:Error).with(_("Invalid URL.")).and_return(true)
          expect(registration_ui).to_not receive(:register_system_and_base_product)

          expect(subject.run).to eq(:abort)
        end
      end

      context "when user skips registration" do
        before do
          allow(Yast::UI).to receive(:UserInput).and_return(:skip_registration, :next)
        end

        it "does not try to register the system and close the dialog" do
          expect(Yast::Popup).to receive(:Warning).with(/Without registration/)
            .and_return(true)
          expect(subject.run).to eq(:skip)
        end

        context "when full_system_media_name and full_system_download_url" \
                " is defined in control.xml" do
          it "reports the media name and the regarding download url to the user" do
            allow(Yast::ProductFeatures).to receive(:GetStringFeature)
              .with("globals", "full_system_media_name").and_return("SLE-15-Packages")
            allow(Yast::ProductFeatures).to receive(:GetStringFeature)
              .with("globals", "full_system_download_url").and_return("https://download.suse.com")
            expect(Yast::Popup).to receive(:Warning).with(/SLE-15-Packages.*download.suse.com/m)
            expect(subject.run).to eq(:skip)
          end
        end

        context "when full_system_media_name and full_system_download_url" \
                " is NOT defined in control.xml" do
          it "does not mention any media information" do
            allow(Yast::ProductFeatures).to receive(:GetStringFeature)
              .with("globals", "full_system_media_name").and_return("")
            allow(Yast::ProductFeatures).to receive(:GetStringFeature)
              .with("globals", "full_system_download_url").and_return("")
            expect(Yast::Popup).to receive(:Warning).with(/Without registration/)
              .and_return(true)
            expect(Yast::Popup).not_to receive(:Warning).with(/Without these media only/)
            expect(subject.run).to eq(:skip)
          end
        end
      end
    end

    context "when system is already registered" do
      let(:registered?) { true }

      context "in installation mode" do
        it "disables widgets" do
          expect(Yast::UI).to receive(:ChangeWidget).with(Id(:action), :Enabled, false)
          allow(Yast::UI).to receive(:ChangeWidget).and_call_original
          allow(subject).to receive(:event_loop).and_return(nil)
          subject.run
        end
      end
    end
  end
end
