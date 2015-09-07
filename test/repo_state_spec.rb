#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::RepoState do
  subject { Registration::RepoState.new(42, true) }
  describe "#restore" do
    it "restores the original repository state" do
      expect(Yast::Pkg).to receive(:SourceSetEnabled).with(42, true)

      subject.restore
    end
  end
end

describe Registration::RepoStateStorage do
  # create a new anonymous instance for each test to avoid test dependencies
  # see http://stackoverflow.com/a/26172556/633234
  subject { Class.new(Registration::RepoStateStorage).instance }
  let(:file) { Registration::RepoStateStorage::REPO_STATE_FILE }

  before do
    allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([42])
    allow(Yast::Pkg).to receive(:SourceGeneralData).with(42)
      .and_return("alias" => "foo")
  end

  describe "#add" do
    it "adds a new repository to the storage" do
      expect { subject.add(42, true) }.to change { subject.repositories.size }.by(1)
    end
  end

  describe "#restore_all" do
    it "calls 'restore' for all repositories" do
      subject.add(42, true)
      expect_any_instance_of(Registration::RepoState).to receive(:restore)
      subject.restore_all
    end
  end

  describe "#write" do
    it "writes the current staus to disk" do
      subject.add(42, true)
      expect(File).to receive(:write).with(file, anything)
      subject.write
    end
  end

  describe "#read" do
    context "the storage file exists" do
      before do
        expect(File).to receive(:exist?).with(file).and_return(true)
        allow(YAML).to receive(:load_file).with(file).and_return("foo" => true)
      end

      it "reads the stored file" do
        expect { subject.read }.to change { subject.repositories.size }.from(0).to(1)
      end

      it "remaps the stored aliases to repository ID" do
        subject.read
        expect(subject.repositories.first.repo_id).to eq(42)
        expect(subject.repositories.first.enabled).to eq(true)
      end

      it "ignores unknown repository aliases" do
        expect(YAML).to receive(:load_file).with(file).and_return("FOO" => true)
        subject.read
        expect(subject.repositories).to be_empty
      end
    end

    context "the storage file does not exist" do
      it "does not fail if the file does not exist" do
        expect(File).to receive(:exist?).with(file).and_return(false)
        expect { subject.read }.to_not raise_error
      end
    end
  end

  describe "#clean" do
    it "removes the storage file if it exists" do
      expect(File).to receive(:exist?).with(file).and_return(true)
      expect(File).to receive(:unlink).with(file)

      subject.clean
    end

    it "does not try removing the file when it does not exist" do
      expect(File).to receive(:exist?).with(file).and_return(false)
      expect(File).to_not receive(:unlink).with(file)

      subject.clean
    end
  end
end
