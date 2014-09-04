#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/exceptions"

describe Registration::ServiceError do

  it "is a PkgError exception" do
    expect(Registration::ServiceError.new("failed", "ServiceFoo")).to be_a(Registration::PkgError)
  end

end
