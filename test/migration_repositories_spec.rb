#! /usr/bin/env rspec
# typed: false

require_relative "spec_helper"

describe Registration::MigrationRepositories do
  describe ".reset" do
    it "resets the selected packages" do
      expect(Yast::Pkg).to receive(:PkgReset)
      expect(Yast::Pkg).to receive(:SetSolverFlags).with("reset" => true)

      Registration::MigrationRepositories.reset
    end
  end

  describe "#activate_services" do
    before do
      expect(Yast::Stage).to receive(:initial).and_return(false)
      expect(Yast::Pkg).to receive(:SetSolverFlags).with("ignoreAlreadyRecommended" => true,
                                                         "dupAllowVendorChange"     => false)
      expect(Yast::Pkg).to receive(:PkgSolve)
      expect(Yast::Pkg).to receive(:PkgUpdateAll)
      expect(Yast::Pkg).to receive(:SourceLoad)
    end

    it "activates the specified services for upgrade" do
      subject.services << "test_service"
      allow(Yast::Pkg).to receive(:ResolvablePreselectPatches)

      subject.activate_services
    end

    it "preselects patches if configured to install them" do
      subject.install_updates = true

      expect(Yast::Pkg).to receive(:ResolvablePreselectPatches)

      subject.activate_services
    end

    it "disables update repositories if updates should not be installed" do
      product = double("test_product", product_type: "base")
      service = double("test_service", product: product)
      repo = 42
      subject.install_updates = false
      subject.services << service

      expect(Yast::Pkg).to_not receive(:ResolvablePreselectPatches)
      expect(Registration::SwMgmt).to receive(:service_repos).with(service, only_updates: true)
        .and_return(["SrcId" => repo])

      expect(Registration::SwMgmt).to receive(:set_repos_state).with([{ "SrcId" => repo }], false)

      subject.activate_services
    end

    it "keeps module update repositories enabled eventhough updates should not be installed" do
      product = double("test_product", product_type: "module")
      service = double("test_service", product: product)

      subject.install_updates = false
      subject.services << service

      # empty list of disabled repositories
      expect(Registration::SwMgmt).to receive(:set_repos_state).with([], false)

      subject.activate_services
    end
  end

  describe "#activate_repositories" do
    before do
      expect(Yast::Pkg).to receive(:SetSolverFlags).with("ignoreAlreadyRecommended" => true,
                                                         "dupAllowVendorChange"     => false)
      expect(Yast::Pkg).to receive(:PkgSolve)
      expect(Yast::Pkg).to receive(:PkgUpdateAll)
      expect(Yast::Pkg).to receive(:SourceLoad)

      allow(Yast::Pkg).to receive(:ResolvablePreselectPatches)
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([])
    end

    it "activates the specified repositories and disables the rest" do
      subject.repositories << 42
      subject.repositories << 43

      expect(Yast::Pkg).to receive(:SourceGetCurrent).with(false).and_return([41, 42, 43, 44])

      expect(Yast::Pkg).to receive(:SourceGeneralData).with(41).and_return("enabled" => true)
      expect(Yast::Pkg).to receive(:SourceGeneralData).with(42).and_return("enabled" => true)
      expect(Yast::Pkg).to receive(:SourceGeneralData).with(43).and_return("enabled" => false)
      expect(Yast::Pkg).to receive(:SourceGeneralData).with(44).and_return("enabled" => false)

      expect(Yast::Pkg).to receive(:SourceSetEnabled).with(41, false)
      expect(Yast::Pkg).to receive(:SourceSetEnabled).with(43, true)

      subject.activate_repositories
    end

    it "preselects patches if configured to install them" do
      subject.install_updates = true
      expect(Yast::Pkg).to receive(:ResolvablePreselectPatches)
      subject.activate_repositories
    end

    it "does not preselect patches if configured to skip them" do
      subject.install_updates = false
      expect(Yast::Pkg).to_not receive(:ResolvablePreselectPatches)
      subject.activate_repositories
    end
  end
end
