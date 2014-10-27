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
        allow(Yast::Installation).to receive(:destdir).and_return("/mnt")
      end

      after(:each) do
        Registration::RepoStateStorage.instance.repositories = []
      end

      it "do nothing if system is not registered" do
        expect(Registration::Registration).to receive(:is_registered?).once.
          and_return(false)
        expect_any_instance_of(SUSE::Connect::Config).to_not receive(:write)
        expect(Yast::Pkg).to_not receive(:SourceSetEnabled)

        subject.run("Write")
      end

      it "creates at target system configuration for suse connect" do
        expect(Registration::Registration).to receive(:is_registered?).once.
          and_return(true)
        expect(Yast::WFM).to receive(:Execute)

        expect(Registration::Helpers).to receive(:write_config)
        expect(Registration::Helpers).to receive(:copy_certificate_to_target)

        expect(Registration::RepoStateStorage.instance).to receive(:repositories).
          and_return([])
        expect(Yast::Pkg).to_not receive(:SourceSetEnabled)

        subject.run("Write")
      end

      it "restores the repository setup" do
        expect(Registration::Registration).to receive(:is_registered?).once.
          and_return(true)
        expect(Yast::WFM).to receive(:Execute)

        expect(Registration::Helpers).to receive(:write_config)
        expect(Registration::Helpers).to receive(:copy_certificate_to_target)

        # changed repository with ID 42, originally enabled
        repo_state = Registration::RepoState.new(42, true)
        Registration::RepoStateStorage.instance.repositories = [repo_state]
        expect(Yast::Pkg).to receive(:SourceSetEnabled).with(42, true)
        expect(Yast::Pkg).to receive(:SourceSaveAll)

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
