#!/usr/bin/env rspec

require_relative "spec_helper"
require "registration/connect_helpers"

describe Registration::ConnectHelpers do
  subject(:helpers) { Registration::ConnectHelpers }

  describe "#catch_registration_errors" do
    it "reports an error with details on timeout" do
      details = _("Make sure that the registration server is reachable and\n" \
        "the connection is reliable.")
      expect(Yast::Report).to receive(:Error).with(
        "Registration: #{_("Connection time out.")}\n\n\nDetails: #{details}"
      )

      helpers.catch_registration_errors(message_prefix: "Registration: ") do
        raise Timeout::Error
      end
    end

    it "reports general errors including the original message" do
      expect(Yast::Report).to receive(:Error)
        .with(/some message/)

      helpers.catch_registration_errors { raise StandardError, "some message" }
    end
  end
end
