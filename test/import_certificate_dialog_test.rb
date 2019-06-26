#! /usr/bin/env rspec
# typed: false

require_relative "spec_helper"

describe Registration::UI::ImportCertificateDialog do
  describe ".run" do
    it "displays the certificate details and returns the user input" do
      allow(Registration::UrlHelpers).to receive(:registration_url)
      # generic UI mocks
      expect(Yast::UI).to receive(:CloseDialog)
      # "Cancel" button must be the default
      expect(Yast::UI).to receive(:SetFocus).with(:cancel)
      allow(Yast::UI).to receive(:GetDisplayInfo).and_return(
        "TextMode" => false,
        "Width"    => 1024,
        "Height"   => 768
      )

      # user pressed the "Import" button
      expect(Yast::UI).to receive(:UserInput).and_return(:import)

      # check the displayed content
      expect(Yast::UI).to receive(:OpenDialog) do |_opt, content|
        # do a simple check: convert the term to String and use a RegExp
        expect(content.to_s).to match(/Organization \(O\):.*WebYaST/)
      end

      cert = Registration::SslCertificate.load_file(fixtures_file("test.pem"))
      expect(
        Registration::UI::ImportCertificateDialog.run(
          cert, Registration::SslErrorCodes::SELF_SIGNED_CERT
        )
      ).to eq(:import)
    end
  end
end
