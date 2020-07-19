#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::Storage::SSLErrors do
  subject { Registration::Storage::SSLErrors.instance }

  describe "#reset" do
    it "resets temporary SSL data to nil" do
      subject.ssl_error_code = 42
      subject.ssl_error_msg = "Error"
      subject.ssl_failed_cert = "failed"

      subject.reset

      expect(subject.ssl_error_code).to be_nil
      expect(subject.ssl_error_msg).to be_nil
      expect(subject.ssl_failed_cert).to be_nil
    end
  end
end
