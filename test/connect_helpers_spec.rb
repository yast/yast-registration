#!/usr/bin/env rspec

require_relative "spec_helper"
require "registration/connect_helpers"

# helper for creating the SCC API error exceptions
def api_error(code: 400, headers: {}, body: {})
  SUSE::Connect::ApiError.new(
    OpenStruct.new(
      code:    code,
      headers: headers,
      body:    body,
      success: code == 200
    )
  )
end

describe Registration::ConnectHelpers do
  subject(:helpers) { Registration::ConnectHelpers }

  describe "#catch_registration_errors" do
    let(:screen_width) { 80 }

    before do
      allow(Yast::Report).to receive(:Error)
      allow(Yast::UI).to receive(:GetDisplayInfo).and_return(
        "TextMode" => true,
        "Width"    => screen_width,
        "Height"   => 25
      )
    end

    it "returns true if not exception is raised" do
      ret = helpers.catch_registration_errors(message_prefix: "Registration: ") do
        # nothing raised here
      end

      expect(ret).to eq(true)
    end

    it "returns false if an exception is raised" do
      ret = helpers.catch_registration_errors(message_prefix: "Registration: ") do
        raise "an error"
      end

      expect(ret).to eq(false)
    end

    context "on timeout" do
      let(:details) do
        _("Make sure that the registration server is reachable and\n" \
          "the connection is reliable.")
      end
      let(:autoinst) { false }

      before do
        allow(Yast::Mode).to receive(:autoinst).and_return(:autoinst?)
      end

      context "and in AutoYaST mode" do
        let(:autoinst?) { true }
        it "shows an error dialog with a retry and details button" do
          expect(Yast2::Popup).to receive(:show)
          # A retry should be provided. So no "common" AY error report.
          expect(Yast::Report).not_to receive(:Error)

          helpers.catch_registration_errors(message_prefix: "Registration: ") do
            raise Timeout::Error
          end
        end
      end

      context "and in a common installation" do
        it "shows an error dialog with a retry and details button" do
          expect(helpers).to receive(:report_error_and_retry?)
            .with("Registration: " + _("Connection timed out."), details)

          helpers.catch_registration_errors(message_prefix: "Registration: ") do
            raise Timeout::Error
          end
        end

        it "retries the given block if selected by the user" do
          expect(helpers).to receive(:report_error_and_retry?).twice
            .with("Registration: " + _("Connection timed out."), details).and_return(true, false)

          helpers.catch_registration_errors(message_prefix: "Registration: ") do
            raise Timeout::Error
          end
        end
      end
    end

    it "reports general errors including the original message" do
      expect(Yast::Report).to receive(:Error)
        .with(/some message/)

      helpers.catch_registration_errors { raise StandardError, "some message" }
    end

    shared_examples "old registration server" do |exception|
      it "does not report 'old registration server' error when using SCC" do
        expect(Registration::UrlHelpers).to receive(:registration_url)
          .and_return(SUSE::Connect::YaST::DEFAULT_URL)

        expect(Yast::Report).to_not receive(:Error).with(/old registration server/)

        helpers.catch_registration_errors { raise exception }
      end

      it "reports 'old registration server' error when not using SCC" do
        expect(Registration::UrlHelpers).to receive(:registration_url)
          .and_return("https://example.com")

        expect(Yast::Report).to receive(:Error).with(/old registration server/)

        expect_any_instance_of(Registration::SmtStatus).to receive(:ncc_api_present?)
          .and_return(true)

        helpers.catch_registration_errors { raise exception }
      end
    end

    shared_examples "reports error and returns false" do |exception|
      before do
        allow(Registration::UrlHelpers).to receive(:registration_url)
          .and_return(SUSE::Connect::YaST::DEFAULT_URL)
        allow(Yast::Report).to receive(:Error)
      end

      it "reports an error" do
        expect(Yast::Report).to receive(:Error)

        helpers.catch_registration_errors { raise exception }
      end

      it "returns false" do
        expect(helpers.catch_registration_errors { raise exception }).to eq(false)
      end
    end

    context "JSON parse error is received" do
      let(:autoinst?) { true }

      before do
        allow(Yast::Mode).to receive(:autoinst).and_return(autoinst?)
        allow(Registration::UrlHelpers).to receive(:registration_url)
          .and_return(SUSE::Connect::YaST::DEFAULT_URL)
      end

      include_examples "old registration server", JSON::ParserError.new("error message")

      context "and in interactive installation" do
        let(:autoinst?) { false }

        it "hiddes the error details in a details button" do
          expect(helpers).to receive(:details_error)
            .with("Registration: " + _("Cannot parse the data from server."), "error message")

          helpers.catch_registration_errors(message_prefix: "Registration: ") do
            raise JSON::ParserError, "error message"
          end
        end
      end
    end

    [400, 401, 500, 42].each do |error_code|
      exception = api_error(code: error_code)

      context "error #{error_code} is received" do
        include_examples "reports error and returns false", exception

        it "logs the exception" do
          expect(helpers.log).to receive(:error).with(/#{exception.response.inspect}/)

          helpers.catch_registration_errors { raise exception }
        end
      end
    end

    context "error 404 is received" do
      include_examples "old registration server", api_error(code: 404)
    end

    context "error 422 is received" do
      context "and 'silent_reg_code_mismatch' param is not set" do
        include_examples "reports error and returns false", api_error(code: 422)
      end

      context "and 'silent_reg_code_mismatch' param is set" do
        let(:error_msg) { "Something went wrong" }
        let(:exception) { api_error(code: 422, body: { "error" => error_msg }) }

        before do
          allow(Registration::UrlHelpers).to receive(:registration_url)
            .and_return(SUSE::Connect::YaST::DEFAULT_URL)
        end

        it "does not report an error" do
          expect(Yast::Report).to_not receive(:Error)

          helpers.catch_registration_errors(silent_reg_code_mismatch: true) { raise exception }
        end

        it "returns false" do
          expect(
            helpers.catch_registration_errors(silent_reg_code_mismatch: true) { raise exception }
          ).to eq(false)
        end
      end
    end

    context "'show_update_hint' parameter is set to true and error 401 is raised" do
      let(:exception) { api_error(code: 401) }

      it "displays the NCC sync hint when using SCC" do
        expect(Registration::UrlHelpers).to receive(:registration_url)
          .and_return(SUSE::Connect::YaST::DEFAULT_URL)

        expect(Yast::Report).to receive(:Error).with(/Synchronization from NCC to SCC/)

        helpers.catch_registration_errors(show_update_hint: true) { raise exception }
      end

      it "does not display the NCC sync hint when not using SCC" do
        expect(Registration::UrlHelpers).to receive(:registration_url).at_least(:once)
          .and_return("https://example.com")

        expect(Yast::Report).to_not receive(:Error).with(/Synchronization from NCC to SCC/)

        helpers.catch_registration_errors(show_update_hint: true) { raise exception }
      end
    end

    exceptions = [
      Registration::PkgError.new,
      Registration::ServiceError.new("Updating service '%s' failed.", "service_foo")
    ]

    exceptions.each do |exception|
      context "exception #{exception} is raised" do
        include_examples "reports error and returns false", exception

        it "reports an error with Pkg details" do
          expect(Yast::Pkg).to receive(:LastError).and_return("PkgLastError")
          expect(Yast::Report).to receive(:Error).with(/Details: PkgLastError/)

          helpers.catch_registration_errors { raise exception }
        end

        it "reports an error without Pkg details if it is empty" do
          expect(Yast::Pkg).to receive(:LastError).and_return("")
          expect(Yast::Report).to_not receive(:Error).with(/Details:/)

          helpers.catch_registration_errors { raise exception }
        end
      end
    end

    network_exceptions = [
      SocketError,
      Errno::ENETUNREACH
    ]

    network_exceptions.each do |exception|
      context "exception #{exception} is raised" do
        before do
          expect(Yast::NetworkService).to receive(:isNetworkRunning).and_return(true)
        end

        include_examples "reports error and returns false", exception
      end
    end

  end
end
