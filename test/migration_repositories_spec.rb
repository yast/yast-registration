#! /usr/bin/env rspec

require_relative "spec_helper"

describe Registration::MigrationRepositories do
  subject { Registration::MigrationRepositories.new }

  describe ".reset" do
    it "resets the distribution upgrade flags and package statuses" do
      expect(Yast::Pkg).to receive(:GetUpgradeRepos).and_return([99])
      expect(Yast::Pkg).to receive(:RemoveUpgradeRepo).with(99)
      expect(Yast::Pkg).to receive(:PkgReset)

      Registration::MigrationRepositories.reset
    end
  end

  describe "#add_service" do
    it "adds repositories belonging to a service" do
      subject.repositories << { "SrcId" => 42 }

      expect(Registration::SwMgmt).to receive(:service_repos).with("service")
        .and_return(["SrcId" => 99])

      subject.add_service("service")
      expect(subject.repositories).to eq([{ "SrcId" => 42 }, { "SrcId" => 99 }])
    end
  end

  describe "#activate" do
    before do
      subject.repositories << { "SrcId" => 42 }

      expect(Yast::Pkg).to receive(:SetSolverFlags).with("ignoreAlreadyRecommended" => true,
                                                         "allowVendorChange"        => false)
      allow(Yast::Pkg).to receive(:PkgSolve)
      expect(Yast::Pkg).to receive(:AddUpgradeRepo).with(42)
    end

    it "activates upgrade from the specified repositories" do
      subject.activate
    end

    it "preselects patches if configured to install them" do
      subject.install_updates = true

      expect(Yast::Pkg).to receive(:ResolvablePreselectPatches)

      subject.activate
    end

    it "skips update repositories if updates should not be installed" do
      subject.install_updates = false
      subject.repositories << { "SrcId" => 44, "is_update_repo" => true }
      expect(Yast::Pkg).to_not receive(:AddUpgradeRepo).with(44)

      subject.activate
    end
  end
end
