#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::UI::WizardClient do
  describe "#main" do
    before do
      allow(Yast::Wizard).to receive(:IsWizardDialog)
      allow(Yast::Wizard).to receive(:CreateDialog)
      allow(Yast::Wizard).to receive(:CloseDialog)
    end

    it "opens a wizard dialog if it is missing" do
      expect(Yast::Wizard).to receive(:IsWizardDialog).and_return(false)
      expect(Yast::Wizard).to receive(:CreateDialog)
      allow(subject).to receive(:run)

      subject.main
    end

    it "uses the current wizard dialog if it exists" do
      expect(Yast::Wizard).to receive(:IsWizardDialog).and_return(true)
      expect(Yast::Wizard).to_not receive(:CreateDialog)
      allow(subject).to receive(:run)

      subject.main
    end
  end

  describe "#run" do
    it "calls run_sequence() method" do
      expect(subject).to receive(:run_sequence)
      subject.main
    end

    it "returns :abort when an exception is raised" do
      expect(subject).to receive(:run_sequence).and_raise("Error")
      allow(Yast::Report).to receive(:Error)
      expect(subject.run).to eq(:abort)
    end
  end

  describe "#run_sequence" do
    it "raises NotImplementedError exception" do
      expect { subject.run_sequence }.to raise_error(NotImplementedError)
    end
  end
end
