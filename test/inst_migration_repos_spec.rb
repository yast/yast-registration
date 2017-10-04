#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/clients/inst_migration_repos"

describe Registration::Clients::InstMigrationRepos do
  before do
    allow(SUSE::Connect::System).to receive(:filesystem_root=)
    allow(Yast::Installation).to receive(:destdir).and_return("/")
    allow(Yast::WFM).to receive(:call)
  end

  it "passes the target path to SUSEConnect" do
    destdir = "/foo"
    expect(Yast::Installation).to receive(:destdir).and_return(destdir).at_least(:once)
    expect(SUSE::Connect::System).to receive(:filesystem_root=).with(destdir)
    subject.main
  end

  it "does not pass the path if it is \"/\"" do
    expect(SUSE::Connect::System).to_not receive(:filesystem_root=)
    subject.main
  end

  it "runs the standard \"migration_repos\" client" do
    expect(Yast::WFM).to receive(:call).with("migration_repos")
    subject.main
  end
end
