#! /usr/bin/env rspec
# typed: false

require_relative "spec_helper"

describe Registration::ServiceError do
  it "is a PkgError exception" do
    expect(Registration::ServiceError.new("failed", "ServiceFoo")).to be_a(Registration::PkgError)
  end
end
