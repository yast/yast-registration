#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::ServiceError do

  it "is a PkgError exception" do
    expect(Registration::ServiceError.new("failed", "ServiceFoo")).to be_a(Registration::PkgError)
  end

end
