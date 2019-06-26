#! /usr/bin/env rspec
# typed: false

require_relative "spec_helper"

describe Registration::UI::OfflineMigrationWorkflow do
  describe "#main" do
    before do
      allow(Yast::Wizard).to receive(:ClearContents)
      allow(Yast::Packages).to receive(:init_called=)
      allow(Yast::Packages).to receive(:Initialize)
      allow(Yast::GetInstArgs).to receive(:going_back)
      allow(File).to receive(:delete)
      allow(File).to receive(:exist?)
      allow(Yast::WFM).to receive(:CallFunction)
      allow(Yast::Stage).to receive(:initial).and_return(true)
    end

    shared_examples "certificate cleanup" do
      it "removes the SSL ceritificate from inst-sys" do
        expect(File).to receive(:exist?)
          .with(Registration::SslCertificate::INSTSYS_SERVER_CERT_FILE)
          .and_return(true)
        expect(Yast::Execute).to receive(:locally).with("trust", "extract",
          "--format=openssl-directory", "--filter=ca-anchors", "--overwrite",
          Registration::SslCertificate::TMP_CA_CERTS_DIR)
        expect(Dir).to receive(:[])
          .with(File.join(Registration::SslCertificate::TMP_CA_CERTS_DIR, "*"))
          .and_return([File.join(Registration::SslCertificate::TMP_CA_CERTS_DIR, "smt.pem")])
        expect(Dir).to receive(:[])
          .with("/etc/pki/trust/anchors/*.pem")
          .and_return(["/etc/pki/trust/anchors/registration_server.pem"])

        var_lib_cert = File.join(Registration::SslCertificate::CA_CERTS_DIR, "/openssl/smt.pem")
        expect(File).to receive(:exist?).with(var_lib_cert).and_return(true)
        expect(File).to receive(:delete).with(var_lib_cert)

        expect(File).to receive(:delete)
          .with(Registration::SslCertificate::INSTSYS_SERVER_CERT_FILE)
        expect(FileUtils).to receive(:rm_rf).with(Registration::SslCertificate::TMP_CA_CERTS_DIR)
        subject.main
      end
    end

    context "when going back" do
      before do
        expect(Yast::GetInstArgs).to receive(:going_back).and_return(true)
        allow(Registration::Registration).to receive(:is_registered?)
      end

      it "returns :back" do
        expect(subject.main).to eq(:back)
      end

      it "does not run rollback when the system is not registered" do
        expect(subject).to_not receive(:rollback)
        subject.main
      end

      context "the system is registered" do
        before do
          expect(Registration::Registration).to receive(:is_registered?).and_return(true)
          allow(Yast::WFM).to receive(:CallFunction).with("registration_sync")
        end

        include_examples "certificate cleanup"

        it "runs rollback" do
          expect(Yast::WFM).to receive(:CallFunction).with("registration_sync")
          subject.main
        end

        it "removes the copied credentials" do
          expect(File).to receive(:exist?).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
            .and_return(true)
          expect(File).to receive(:delete).with(SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE)
          subject.main
        end
      end
    end

    it "runs the 'inst_migration_repos' client" do
      expect(Yast::WFM).to receive(:CallFunction).with("inst_migration_repos", anything)
      subject.main
    end

    it "returns the 'inst_migration_repos' result" do
      expect(Yast::WFM).to receive(:CallFunction).with("inst_migration_repos", anything)
        .and_return(:foo)
      expect(subject.main).to eq(:foo)
    end

    describe "it updates the add-on records" do
      let(:new_id) { 23 }
      let(:product_dir) { "" }
      let(:url) { "dir:///update/000/repo" }

      before do
        expect(Yast::Pkg).to receive(:SourceGetCurrent).and_return([new_id])
        expect(Yast::Pkg).to receive(:SourceGeneralData).with(new_id).and_return(
          "url"         => url,
          "product_dir" => product_dir
        )
      end

      it "updates the repository ID" do
        addons = [
          {
            "media_url"   => url,
            "media"       => 42,
            "product_dir" => product_dir,
            "product"     => "Driver Update 0"
          }
        ]

        Yast::AddOnProduct.add_on_products = addons

        expect { subject.main }.to change { Yast::AddOnProduct.add_on_products.first["media"] }
          .from(42).to(new_id)
      end

      it "ignores the alias query in the addon URL" do
        url2 = "dir:///update/000/repo?alias=DriverUpdate0"

        addons = [
          {
            "media_url"   => url2,
            "media"       => 42,
            "product_dir" => product_dir,
            "product"     => "Driver Update 0"
          }
        ]

        Yast::AddOnProduct.add_on_products = addons

        expect { subject.main }.to change { Yast::AddOnProduct.add_on_products.first["media"] }
          .from(42).to(new_id)
      end
    end

    context "the 'inst_migration_repos' client returns :rollback" do
      before do
        expect(Yast::WFM).to receive(:CallFunction).with("inst_migration_repos", anything)
          .and_return(:rollback)
        allow(Yast::WFM).to receive(:CallFunction).with("registration_sync")
      end

      include_examples "certificate cleanup"

      it "runs the 'registration_sync' client" do
        expect(Yast::WFM).to receive(:CallFunction).with("registration_sync")
        subject.main
      end

      it "return :back" do
        expect(subject.main).to eq(:back)
      end
    end
  end
end
