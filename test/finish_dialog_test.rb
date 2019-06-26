#! /usr/bin/env rspec
# typed: false

require_relative "./spec_helper"

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
        expect(Registration::Registration).to receive(:is_registered?).once
          .and_return(false)
        expect(Yast::Pkg).to_not receive(:SourceSetEnabled)

        subject.run("Write")
      end

      context "the system is registered" do
        before do
          expect(Registration::Registration).to receive(:is_registered?).and_return(true)

          allow(Registration::Helpers).to receive(:write_config)
          allow(Registration::Helpers).to receive(:copy_certificate_to_target)
          allow(Registration::RepoStateStorage.instance).to receive(:repositories)
            .and_return([])

          allow(FileUtils).to receive(:mv)
          allow(File).to receive(:exist?).and_return(false)
        end

        it "creates at target system configuration for suse connect" do
          expect(Registration::Helpers).to receive(:write_config)
          expect(Registration::Helpers).to receive(:copy_certificate_to_target)

          subject.run("Write")
        end

        it "restores the repository setup" do
          # changed repository with ID 42, originally enabled
          repo_state = Registration::RepoState.new(42, true)
          allow(Registration::RepoStateStorage.instance).to receive(:repositories)
            .and_return([repo_state])
          expect(Yast::Pkg).to receive(:SourceSetEnabled).with(42, true)
          expect(Yast::Pkg).to receive(:SourceSaveAll)

          subject.run("Write")
        end

        it "removes the old NCC credentials" do
          ncc_credentials = "/mnt/etc/zypp/credentials.d/NCCcredentials"
          expect(File).to receive(:exist?).with(ncc_credentials).and_return(true)
          expect(File).to receive(:delete).with(ncc_credentials)

          subject.run("Write")
        end
      end
    end

    it "raises RuntimeError if unknown action passed as first parameter" do
      expect { subject.run("non_existing_action") }.to(
        raise_error(RuntimeError)
      )
    end
  end
end
