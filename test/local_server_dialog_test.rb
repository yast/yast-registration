#! /usr/bin/env rspec

require_relative "spec_helper"
require "yast"

require "registration/ui/local_server_dialog"


describe Registration::UI::LocalServerDialog do
  let(:ui) { double("Yast::UI") }
  let(:url) { "https://example.com/register" }

  before do
    # generic UI stubs for the dialog
    stub_const("Yast::UI", ui)

    expect(ui).to receive(:OpenDialog)
    expect(ui).to receive(:CloseDialog)
    expect(ui).to receive(:SetFocus)
  end

  it "returns the URL entered by user" do
    # stub the user interaction in the dialog
    expect(ui).to receive(:UserInput).and_return(:ok)
    # the input field contains the URL
    expect(ui).to receive(:QueryWidget).and_return(url)

    expect(Registration::UI::LocalServerDialog.run(url)).to eq(url)
  end

  it "returns nil when the dialog is canceled" do
    # stub the user interaction in the dialog
    expect(ui).to receive(:UserInput).and_return(:cancel)

    expect(Registration::UI::LocalServerDialog.run(url)).to be_nil
  end

end
