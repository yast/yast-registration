#! /usr/bin/env rspec

require_relative "spec_helper"
require "yaml"

describe Registration::SwMgmt do
  subject { Registration::SwMgmt }

  let(:service_name) { "SLES" }
  let(:repos) do
    {
      # installation repository, not from registration
      0 => {
        "alias" => "SLES12", "autorefresh" => false,
        "base_urls" => ["cd:///"],
        "enabled" => true, "is_update_repo" => false, "keeppackages" => false,
        "mirror_list" => "", "name" => "SLES12", "priority" => 99, "product_dir" => "",
        "service" => "", "type" => "SUSE",
        "url" => "cd:///"
      },
      # pool repo from service
      1 => {
        "alias" => "SLES:SLES12-Pool", "autorefresh" => true,
        "base_urls" => ["https://nu.novell.com/suse/x86_64/update/SLE-SERVER/12-POOL"],
        "enabled" => true, "is_update_repo" => false, "keeppackages" => false,
        "mirror_list" => "", "name" => "SLES12-Pool", "priority" => 99, "product_dir" => "",
        "service" => service_name, "type" => "YUM",
        "url" => "https://nu.novell.com/suse/x86_64/update/SLE-SERVER/12-POOL"
      },
      # update repo from service
      2 => {
        "alias" => "SLES:SLES12-Updates", "autorefresh" => true,
        "base_urls" => ["https://nu.novell.com/suse/x86_64/update/SLE-SERVER/12"],
        "enabled" => true, "is_update_repo" => true, "keeppackages" => false,
        "mirror_list" => "", "name" => "SLES12-Updates", "priority" => 99, "product_dir" => "",
        "service" => service_name, "type" => "YUM",
        "url" => "https://nu.novell.com/suse/x86_64/update/SLE-SERVER/12"
      },
      # update repo from a different service
      3 => {
        "alias" => "Another:SLES12-Updates", "autorefresh" => true,
        "base_urls" => ["https://nu.novell.com/suse/x86_64/update/SLE-SERVER/12"],
        "enabled" => true, "is_update_repo" => true, "keeppackages" => false,
        "mirror_list" => "", "name" => "SLES12-Updates", "priority" => 99, "product_dir" => "",
        "service" => "Another", "type" => "YUM",
        "url" => "https://nu.novell.com/suse/x86_64/update/SLE-SERVER/12"
      }
    }
  end

  describe ".init" do
    before do
      allow(Yast::PackageLock).to receive(:Connect).and_return("connected" => connected)
    end

    context "when the libzypp lock can be obtained" do
      let(:connected) { true }
      let(:source_restore_result) { true }

      it "initializes package management and returns Pkg.:SourceRestore result" do
        expect(Yast::PackageCallbacks).to receive(:InitPackageCallbacks)
        expect(Yast::Pkg).to receive(:TargetInitialize)
        expect(Yast::Pkg).to receive(:TargetLoad)
        expect(Yast::Pkg).to receive(:SourceRestore).and_return(source_restore_result)

        expect(subject.init).to eq(source_restore_result)
      end
    end

    context "when the libzypp lock cannot be obtained" do
      let(:connected) { false }

      it "returns false" do
        expect(subject.init).to eq(false)
      end
    end
  end

  describe ".service_repos" do
    let(:service) { double }

    before do
      expect(service).to receive(:name).and_return(service_name)

      expect(Yast::Pkg).to receive(:SourceGetCurrent).with(false).and_return(repos.keys)
      repos.each do |id, repo|
        expect(Yast::Pkg).to receive(:SourceGeneralData).with(id).and_return(repo)
      end
    end

    it "returns list of repositories belonging to a service" do
      expect(subject.service_repos(service)).to eq([repos[1], repos[2]])
    end

    it "optionally returns only update repositories" do
      expect(subject.service_repos(service, only_updates: true)).to eq([repos[2]])
    end
  end

  describe ".base_product_to_register" do
    it "returns base product base version and release_type" do
      expect(subject).to(receive(:find_base_product)
        .and_return("name" => "SLES", "arch" => "x86_64",
          "version" => "12.1-1.47", "version_version" => "12.1", "flavor" => "DVD"))

      expect(subject.base_product_to_register).to eq("name" => "SLES",
        "arch" => "x86_64", "version" => "12.1", "release_type" => nil)
    end
  end

  describe ".add_services" do
    let(:service_url) { "https://example.com/foo/bar?credentials=TEST_credentials" }
    let(:credentials) { SUSE::Connect::Credentials.new("user", "password", "file") }
    let(:product_service) do
      SUSE::Connect::Remote::Service.new(
        "name"    => service_name,
        "url"     => service_url,
        "product" => {}
      )
    end

    before do
      expect(Yast::Pkg).to receive(:SourceSaveAll).and_return(true).twice
      expect(Yast::Pkg).to receive(:ServiceRefresh).with(service_name).and_return(true)
      expect(Yast::Pkg).to receive(:ServiceSave).with(service_name).and_return(true)
      expect_any_instance_of(SUSE::Connect::Credentials).to receive(:write)

      allow(Yast::Pkg).to receive(:SourceGetCurrent).with(false).and_return(repos.keys)
      repos.each do |id, repo|
        allow(Yast::Pkg).to receive(:SourceGeneralData).with(id).and_return(repo)
      end

      expect(Yast::Mode).to receive(:update).and_return(false)
    end

    it "it creates a new service if the service does not exist yet" do
      expect(Yast::Pkg).to receive(:ServiceAliases).and_return([])
      expect(Yast::Pkg).to receive(:ServiceAdd).with(service_name, service_url).and_return(true)
      expect(Yast::Pkg).to receive(:ServiceSet).with(
        service_name, hash_including("autorefresh" => true)).and_return(true)
      expect { subject.add_service(product_service, credentials) }.to_not raise_error
    end

    it "updates the existing service if the service already exists" do
      expect(Yast::Pkg).to receive(:ServiceAliases).and_return([service_name])
      expect(Yast::Pkg).to receive(:ServiceSet).with(
        service_name, hash_including("url" => service_url)).and_return(true)
      expect { subject.add_service(product_service, credentials) }.to_not raise_error
    end
  end

  describe ".copy_old_credentials" do
    let(:root_dir) { "/mnt" }
    let(:target_dir) { SUSE::Connect::Credentials::DEFAULT_CREDENTIALS_DIR }

    before do
      expect(subject).to receive(:zypp_config_writable!)

      expect(File).to receive(:exist?).with(target_dir).and_return(false)
      expect(FileUtils).to receive(:mkdir_p).with(target_dir)
    end

    it "does not fail when the old credentials are missing" do
      expect(File).to receive(:exist?).with(File.join(root_dir, target_dir, "NCCcredentials"))
        .and_return(false)
      expect(File).to receive(:exist?).with(File.join(root_dir, target_dir, "SCCcredentials"))
        .and_return(false)

      # no copy
      expect(FileUtils).to receive(:cp).never

      expect { subject.copy_old_credentials(root_dir) }.to_not raise_error
    end

    it "copies old NCC credentials at upgrade" do
      expect(File).to receive(:exist?).with(File.join(root_dir, target_dir, "NCCcredentials"))
        .and_return(true)
      expect(File).to receive(:exist?).with(File.join(root_dir, target_dir, "SCCcredentials"))
        .and_return(false)

      expect(FileUtils).to receive(:cp).with(File.join(root_dir, target_dir, "NCCcredentials"),
        File.join(target_dir, "SCCcredentials"))
      expect(SUSE::Connect::Credentials).to receive(:read)

      expect { subject.copy_old_credentials(root_dir) }.to_not raise_error
    end

    it "copies old SCC credentials at upgrade" do
      expect(File).to receive(:exist?).with(File.join(root_dir, target_dir, "NCCcredentials"))
        .and_return(false)
      expect(File).to receive(:exist?).with(File.join(root_dir, target_dir, "SCCcredentials"))
        .and_return(true)

      expect(FileUtils).to receive(:cp).with(File.join(root_dir, target_dir, "SCCcredentials"),
        File.join(target_dir, "SCCcredentials"))
      expect(SUSE::Connect::Credentials).to receive(:read)

      expect { subject.copy_old_credentials(root_dir) }.to_not raise_error
    end
  end

  describe ".find_addon_updates" do
    it "returns new available addons for installed addons" do
      # installed: SLES11-SP2 + SLE11-SP2-SDK + SLE11-SP2-Webyast
      expect(Yast::Pkg).to receive(:ResolvableProperties).with("", :product, "") \
        .and_return(load_yaml_fixture("products_sp2_update.yml"))
      # available: SDK, HA, HA-GEO, ...
      available_addons = load_yaml_fixture("available_addons.yml")

      addon_updates = subject.find_addon_updates(available_addons)
      # an update only for SDK addon is available
      expect(addon_updates.size).to eq 1
      expect(addon_updates.first.label).to \
        eq("SUSE Linux Enterprise Software Development Kit 12 x86_64")
    end
  end

  describe ".select_addon_products" do
    it "selects new addon products for installation" do
      legacy_services = load_yaml_fixture("legacy_module_services.yml")

      expect(::Registration::Storage::Cache).to receive(:instance)
        .and_return(double("addon_services" => legacy_services))
      expect(subject).to receive(:service_repos).with(legacy_services.first)
        .and_return(load_yaml_fixture("legacy_module_repositories.yml"))
      expect(Yast::Pkg).to receive(:ResolvableProperties)
        .and_return(load_yaml_fixture("products_legacy_installation.yml"))
      expect(Yast::Pkg).to receive(:ResolvableInstall).with("sle-module-legacy", :product)

      subject.select_addon_products
    end
  end

  describe ".products_from_repo" do
    before do
      expect(Yast::Pkg).to receive(:ResolvableProperties)
        .and_return(load_yaml_fixture("products_legacy_installation.yml"))
    end

    it "Returns product resolvables from the specified repository" do
      expect(subject.products_from_repo(5).size).to eq 1
    end

    it "Returns empty list if not product is found" do
      expect(subject.products_from_repo(255)).to be_empty
    end
  end

  describe ".select_product_addons" do
    # just the sle-module-legacy product
    let(:products) { [load_yaml_fixture("products_legacy_installation.yml").first] }

    it "selects remote addons matching the product resolvables" do
      available_addons = load_yaml_fixture("available_addons.yml")

      # expect the sle-module-legacy product to be selected
      expect(available_addons[4]).to receive(:selected)
      subject.select_product_addons(products, available_addons)
    end

    it "reports an error when the matching remote addon is not found" do
      available_addons = []

      expect(Yast::Report).to receive(:Error).with(/Cannot find remote product/)
      subject.select_product_addons(products, available_addons)
    end
  end

  describe ".installed_products" do
    let(:products) { load_yaml_fixture("products_legacy_installation.yml") }

    it "returns installed products" do
      expect(Yast::Pkg).to receive(:ResolvableProperties).and_return(products)
      # only the SLES product in the list is installed
      expect(subject.installed_products).to eq([products[1]])
    end
  end

  describe ".find_base_product" do
    context "in installed system" do
      let(:products) { load_yaml_fixture("products_legacy_installation.yml") }
      it "returns installed products" do
        allow(Yast::Stage).to receive(:initial).and_return(false)
        expect(Yast::Pkg).to receive(:ResolvableProperties).and_return(products)
        # the SLES product in the list is installed
        expect(subject.find_base_product).to eq(products[1])
      end
    end

    context "at installation" do
      let(:products) { load_yaml_fixture("products_sp2_update.yml") }
      it "returns the product from the installation medium" do
        allow(Yast::Stage).to receive(:initial).and_return(true)
        expect(Yast::Pkg).to receive(:ResolvableProperties).and_return(products)
        # the SLES product in the list is installed
        expect(subject.find_base_product).to eq(products[3])
      end
    end
  end

  describe ".remove_service" do
    let(:service) { "service" }

    before do
      expect(Yast::Pkg).to receive(:ServiceDelete).with(service).and_return(true)
    end

    it "removes the service and saves the repository configuration" do
      expect(Yast::Pkg).to receive(:SourceSaveAll).and_return(true)

      expect { subject.remove_service(service) }.to_not raise_error
    end

    it "raises an exception when saving failes after service removal" do
      expect(Yast::Pkg).to receive(:SourceSaveAll).and_return(false)

      expect { subject.remove_service(service) }.to raise_error(::Registration::PkgError)
    end
  end
end
