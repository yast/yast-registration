#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/clients/inst_migration_repos"

describe Registration::Clients::InstMigrationRepos do
  before do
    allow(Yast::Installation).to receive(:destdir).and_return("/")
    allow(Yast::WFM).to receive(:call)
  end

  it "runs the standard \"migration_repos\" client" do
    expect(Yast::WFM).to receive(:call).with("migration_repos")
    subject.main
  end
end
