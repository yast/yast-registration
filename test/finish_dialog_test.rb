#! /usr/bin/env rspec

require_relative "./spec_helper"

require "registration/finish_dialog"

describe ::Registration::FinishDialog do

  subject { ::Registration::FinishDialog.new }

  describe "#run" do
    describe "first paramater \"Info\"" do
      it "returns info entry hash with scenarios in \"when\" key" do
        result = subject.run("Info")

        expect(result["when"]).to_not be_empty
      end

    end

    describe "first parameter \"Write\"" do
      before(:each) do
        stub_const("Yast::Installation", double(:destdir => "/mnt"))
      end


      it "do nothing if system is not registered" do
        expect(Registration::Registration).to receive(:is_registered?).once.
          and_return(false)
        expect_any_instance_of(SUSE::Connect::Config).to_not receive(:write)

        subject.run("Write")
      end

      it "creates at target system configuration for suse connect" do
        expect(Registration::Registration).to receive(:is_registered?).once.
          and_return(true)
        expect(Yast::WFM).to receive(:Execute)

        expect(Registration::Helpers).to receive(:write_config)
        expect(Registration::Helpers).to receive(:copy_certificate_to_target)

        subject.run("Write")
      end
    end

    it "raises RuntimeError if unknown action passed as first parameter" do
      expect{subject.run("non_existing_action")}.to(
        raise_error(RuntimeError)
      )
    end
  end
end
