#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::ImportCertificateDialog do

  describe ".run" do
    it "displays the certificate details and returns the user input" do
      # generic UI mocks
      expect(Yast::UI).to receive(:CloseDialog)
      # "Cancel" button must be the default
      expect(Yast::UI).to receive(:SetFocus).with(:cancel)
      allow(Yast::UI).to receive(:GetDisplayInfo).and_return({
          "TextMode" => false,
          "Width" => 1024,
          "Height" => 768
      })

      # user pressed the "Import" button
      expect(Yast::UI).to receive(:UserInput).and_return(:import)

      # check the displayed content
      expect(Yast::UI).to receive(:OpenDialog) do |arg1, arg2|
        # do a simple check: convert the term to String and use a RegExp
        expect(arg2.to_s).to match(/Organization \(O\):.*WebYaST/)
      end

      cert = Registration::SslCertificate.load_file(fixtures_file("test.pem"))
      expect(Registration::UI::ImportCertificateDialog.run(cert)).to eq(:import)
    end
  end

end
