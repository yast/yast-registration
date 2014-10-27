#! /usr/bin/env rspec

require_relative "spec_helper"
require "registration/ui/local_server_dialog"

describe Registration::UI::LocalServerDialog do
  let(:url) { "https://example.com/register" }

  before do
    # generic UI stubs for the dialog
    expect(Yast::UI).to receive(:OpenDialog)
    expect(Yast::UI).to receive(:CloseDialog)
    allow(Yast::UI).to receive(:SetFocus)
  end

  it "returns the URL entered by user" do
    # stub the user interaction in the dialog
    expect(Yast::UI).to receive(:UserInput).and_return(:ok)
    # the input field contains the URL
    expect(Yast::UI).to receive(:QueryWidget).twice.and_return(url)

    expect(Registration::UI::LocalServerDialog.run("")).to eq(url)
  end

  it "returns nil when the dialog is canceled" do
    # stub the user interaction in the dialog
    expect(Yast::UI).to receive(:UserInput).and_return(:cancel)

    expect(Registration::UI::LocalServerDialog.run("")).to be_nil
  end

  it "reports error when URL is not valid" do
    # stub the user interaction in the dialog:
    # cancel the dialog after displaying an error for invalid URL
    expect(Yast::UI).to receive(:UserInput).and_return(:ok, :cancel)
    # the input field contains invalid URL
    expect(Yast::UI).to receive(:QueryWidget).and_return("foobar")

    expect(Yast::Report).to receive(:Error)
    expect(Registration::UI::LocalServerDialog.run(url)).to be_nil
  end

end
