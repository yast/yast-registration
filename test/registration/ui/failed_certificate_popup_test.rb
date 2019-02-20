#!/usr/bin/env rspec
# ------------------------------------------------------------------------------
# Copyright (c) 2018 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require_relative "../../spec_helper"
require "registration/ui/failed_certificate_popup"

describe Registration::UI::FailedCertificatePopup do

  let(:ssl_error) do
    "SSL_connect returned=1 errno=0 state=error: certificate verify failed " \
      "(unable to get local issuer certificate)"
  end

  let(:error_code) { Registration::SslErrorCodes::NO_LOCAL_ISSUER_CERTIFICATE }

  let(:ssl_cert) do
    Registration::SslCertificate.load_file(fixtures_file("test.pem"))
  end

  subject do
    Registration::UI::FailedCertificatePopup.new(ssl_error, ssl_cert, error_code)
  end

  before do
    allow(Yast::Report).to receive(:LongError)
    allow(Yast::Stage).to receive(:initial).and_return(false)
  end

  # the instance method
  describe "#show" do
    it "displays the certificate details" do
      expect(Yast::Report).to receive(:LongError).with(/Organization \(O\): .*WebYaST/)
      subject.show
    end

    it "displays the certificate import hints" do
      expect(Yast::Report).to receive(:LongError)
        .with(/Save the server certificate in PEM format to file/)
      subject.show
    end

    it "suggests to call the install_ssl_certificates script in inst-sys" do
      expect(Yast::Stage).to receive(:initial).and_return(true)
      expect(Yast::Report).to receive(:LongError)
        .with(/install_ssl_certificates/)
      subject.show
    end
  end

  # the class method
  describe ".show" do
    it "displays the failed certificate popup" do
      expect_any_instance_of(Registration::UI::FailedCertificatePopup).to receive(:show)
      Registration::UI::FailedCertificatePopup.show(ssl_error, ssl_cert, error_code)
    end
  end
end
