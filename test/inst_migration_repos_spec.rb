#! /usr/bin/env rspec

require_relative "spec_helper"

require "registration/clients/inst_migration_repos"

describe Registration::Clients::InstMigrationRepos do
  let(:destdir) { "/mnt" }
  let(:sle12_cert) { File.join(destdir, SUSE::Connect::YaST::SERVER_CERT_FILE) }
  let(:sle11_cert) { File.join(destdir, "/etc/ssl/certs/registration-server.pem") }

  before do
    allow(Yast::WFM).to receive(:call)
    allow(Yast::Installation).to receive(:destdir).and_return(destdir)
    allow(Registration::SwMgmt).to receive(:copy_old_credentials)
    allow(File).to receive(:exist?).and_return(false)
  end

  it "runs the standard \"migration_repos\" client" do
    allow(Yast::Installation).to receive(:destdir).and_return("/")
    expect(Yast::WFM).to receive(:call).with("migration_repos", anything)
    subject.main
  end

  it "imports the old credentials" do
    expect(Registration::SwMgmt).to receive(:copy_old_credentials)
    subject.main
  end

  it "imports the old SLE12 SSL certificate" do
    expect(File).to receive(:exist?).with(sle12_cert).and_return(true)
    expect(File).to receive(:read).with(sle12_cert).and_return(
      File.read(fixtures_file("test.pem"))
    )
    expect_any_instance_of(Registration::SslCertificate).to receive(:import_to_instsys)

    subject.main
  end

  it "imports the old SLE11 SSL certificate" do
    expect(File).to receive(:exist?).with(sle11_cert).and_return(true)
    expect(File).to receive(:read).with(sle11_cert).and_return(
      File.read(fixtures_file("test.pem"))
    )
    expect_any_instance_of(Registration::SslCertificate).to receive(:import_to_instsys)

    subject.main
  end
end
