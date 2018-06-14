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

      before do
        expect(Yast::PackageCallbacks).to receive(:InitPackageCallbacks)
        expect(Yast::Pkg).to receive(:TargetInitialize).and_return(true)
        expect(Yast::Pkg).to receive(:TargetLoad).and_return(true)
      end

      it "initializes package management" do
        expect(Yast::Pkg).to receive(:SourceRestore).and_return(true)

        subject.init
      end

      it "raises SourceRestoreError exception when the repository restore fails" do
        expect(Yast::Pkg).to receive(:SourceRestore).and_return(false)

        expect { subject.init }.to raise_exception(Registration::SourceRestoreError)
      end
    end

    context "when the libzypp lock cannot be obtained" do
      let(:connected) { false }

      it "raises an PkgError exception" do
        expect { subject.init }.to raise_error(Registration::PkgError)
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

  describe ".installer_update_base_product" do
    let(:base_product) do
      instance_double(Y2Packager::Product, name: "dummy", version: "15.0", arch: "x86_64")
    end
    let(:available_products) { [base_product] }

    before do
      allow(Y2Packager::Product).to receive(:available_base_products).and_return(available_products)
    end

    it "returns nil if the given self_update_id is empty" do
      expect(subject.installer_update_base_product("")).to eq(nil)
    end

    context "when there is no base product available" do
      let(:available_products) { [] }

      it "returns nil" do
        allow(Y2Packager::Product).to receive(:available_base_products).and_return([])
        expect(subject.installer_update_base_product("self_update_id")).to eq(nil)
      end
    end

    context "when there is some product available" do
      it "returns a hash with the product keys 'name', 'version', 'arch' and 'release_type' " do
        product = subject.installer_update_base_product("self_update_id")
        expect(product).to be_a(Hash)
        expect(product.keys.size).to eq(4)
        expect(product).to include("name", "version", "arch", "release_type")
      end

      it "uses the given self_update_id as the product name returned" do
        product = subject.installer_update_base_product("self_update_id")
        expect(product["name"]).to eq("self_update_id")
      end
    end
  end

  describe ".base_product_to_register" do
    it "returns nil if not able to find a product" do
      expect(subject).to receive(:find_base_product).and_return(nil)

      expect(subject.base_product_to_register).to eq(nil)
    end

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
      expect(Yast::Pkg).to receive(:ServiceForceRefresh).with(service_name).and_return(true)
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
        service_name, hash_including("autorefresh" => true)
      ).and_return(true)
      expect { subject.add_service(product_service, credentials) }.to_not raise_error
    end

    it "updates the existing service if the service already exists" do
      expect(Yast::Pkg).to receive(:ServiceAliases).and_return([service_name])
      expect(Yast::Pkg).to receive(:ServiceSet).with(
        service_name, hash_including("url" => service_url)
      ).and_return(true)
      expect { subject.add_service(product_service, credentials) }.to_not raise_error
    end
  end

  describe ".copy_old_credentials" do
    let(:root_dir) { "/mnt" }
    let(:target_dir) { SUSE::Connect::YaST::DEFAULT_CREDENTIALS_DIR }
    let(:ncc_credentials) { File.join(root_dir, target_dir, "NCCcredentials") }
    let(:scc_credentials) { File.join(root_dir, target_dir, "SCCcredentials") }

    before do
      expect(File).to receive(:exist?).with(target_dir).and_return(false)
      allow(File).to receive(:file?).and_return(true)
      expect(FileUtils).to receive(:mkdir_p).with(target_dir)
    end

    it "does not fail when the old credentials are missing" do
      expect(Dir).to receive(:[]).with(File.join(root_dir, target_dir, "*"))
        .and_return([])

      # no copy
      expect(FileUtils).to receive(:cp).never

      expect { subject.copy_old_credentials(root_dir) }.to_not raise_error
    end

    it "copies old NCC credentials at upgrade" do
      expect(Dir).to receive(:[]).with(File.join(root_dir, target_dir, "*"))
        .and_return([ncc_credentials])

      expect(subject).to receive(:`).with("cp -a " + ncc_credentials + " " +
        File.join(target_dir, "SCCcredentials"))
      expect(SUSE::Connect::YaST).to receive(:credentials).and_return(OpenStruct.new)

      subject.copy_old_credentials(root_dir)
    end

    it "prefers the SCC credentials if both NCC and SCC credentials are present" do
      # deliberately return the SCC credentials first here
      expect(Dir).to receive(:[]).with(File.join(root_dir, target_dir, "*"))
        .and_return([scc_credentials, ncc_credentials])

      # copy the credentials in the NCC, SCC order (bsc#1096813)
      expect(subject).to receive(:`).with("cp -a " + ncc_credentials + " " +
        File.join(target_dir, "SCCcredentials")).ordered
      expect(subject).to receive(:`).with("cp -a " + scc_credentials + " " +
        File.join(target_dir, "SCCcredentials")).ordered

      allow(SUSE::Connect::YaST).to receive(:credentials).and_return(OpenStruct.new)

      subject.copy_old_credentials(root_dir)
    end

    it "copies old SCC credentials at upgrade" do
      expect(Dir).to receive(:[]).with(File.join(root_dir, target_dir, "*"))
        .and_return([scc_credentials])

      expect(subject).to receive(:`).with("cp -a " + scc_credentials + " " +
        File.join(target_dir, "SCCcredentials"))
      expect(SUSE::Connect::YaST).to receive(:credentials).and_return(OpenStruct.new)

      subject.copy_old_credentials(root_dir)
    end

    it "copies old SMT credentials at upgrade" do
      smt_credentials = File.join(root_dir, target_dir, "SMT-http_smt_example_com")
      expect(Dir).to receive(:[]).with(File.join(root_dir, target_dir, "*"))
        .and_return([smt_credentials])

      expect(subject).to receive(:`).with("cp -a " + smt_credentials + " " +
        File.join(target_dir, "SMT-http_smt_example_com"))
      expect(SUSE::Connect::YaST).to receive(:credentials).and_return(OpenStruct.new)

      subject.copy_old_credentials(root_dir)
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
    let(:legacy_services) { load_yaml_fixture("legacy_module_services.yml") }

    before do
      allow_any_instance_of(Yast::ProductPatterns).to receive(:names).and_return([])
      allow_any_instance_of(Yast::ProductPatterns).to receive(:select)

      allow(subject).to receive(:service_repos).with(legacy_services.first)
        .and_return(load_yaml_fixture("legacy_module_repositories.yml"))
      allow(Yast::Pkg).to receive(:ResolvableProperties)
        .and_return(load_yaml_fixture("products_legacy_installation.yml"))
      allow(Yast::Pkg).to receive(:ResolvableInstall).with("sle-module-legacy", :product)
    end

    it "selects new addon products for installation" do
      expect(Yast::Pkg).to receive(:ResolvableInstall).with("sle-module-legacy", :product)

      subject.select_addon_products(legacy_services)
    end

    it "selects the default patterns for the selected products" do
      expect_any_instance_of(Yast::ProductPatterns).to receive(:select)

      subject.select_addon_products(legacy_services)
    end

    context "when no services list is given" do
      before do
        allow(::Registration::Storage::Cache).to receive(:instance)
          .and_return(double("addon_services" => legacy_services))
      end

      it "defaults to the cached list of addon services" do
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("sle-module-legacy", :product)

        subject.select_addon_products
      end
    end

    context "during update" do
      before do
        allow(Yast::Mode).to receive(:update).and_return(true)
      end

      it "does not select default patterns for the selected products" do
        expect(Yast::ProductPatterns).to_not receive(:new)

        subject.select_addon_products(legacy_services)
      end
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
      expect(available_addons[10]).to receive(:selected)
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
    before do
      # mapping of the "system-installation()" provides
      allow(Y2Packager::ProductReader).to receive(:installation_package_mapping)
        .and_return("SLES"     => "skelcd-control-SLES",
                    "SLED"     => "skelcd-control-SLED",
                    "SLES_SAP" => "skelcd-control-SLES_SAP")
    end

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

      before do
        allow(Yast::Stage).to receive(:initial).and_return(true)
      end

      it "returns the selected product if a product is selected" do
        expect(Yast::Pkg).to receive(:ResolvableProperties).and_return(products).exactly(3).times
        # sanity check: just make sure the fixture contains the expected data
        expect(products.any? { |p| p["status"] == :selected })

        # the SLES product in the list is installed
        expect(subject.find_base_product).to eq(products[3])
      end

      it "returns the product from the installation medium if no product is selected" do
        # patch the fixture so no product is selected
        products2 = products.dup
        products2[3]["status"] = :available
        # sanity check: just make sure the fixture was patched correctly
        expect(products2.none? { |p| p["status"] == :selected })

        expect(Yast::Pkg).to receive(:ResolvableProperties).and_return(products2).exactly(3).times
        # the SLES product in the list is installed
        expect(subject.find_base_product).to eq(products[3])
      end

      it "ignores a selected product not marked by the `system-installation()` provides" do
        products3 = [{ "name" => "foo", "status" => :selected },
                     { "name" => "SLES", "status" => :selected }]

        expect(Yast::Pkg).to receive(:ResolvableProperties).and_return(products3).exactly(3).times
        # the selected product is ignored, the result is nil
        expect(subject.find_base_product).to eq(products3[1])
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

  describe ".set_repos_state" do
    it "sets the repository state and stores the original state" do
      repos = [{ "SrcId" => 42, "enabled" => true }]

      expect(Yast::Pkg).to receive(:SourceSetEnabled).with(42, false)
      expect_any_instance_of(Registration::RepoStateStorage).to receive(:add)
        .with(42, true)

      subject.set_repos_state(repos, false)
    end
  end

  describe ".update_product_renames" do
    it "forwards the product renames to the AddOnProduct module" do
      expect(Yast::AddOnProduct).to receive(:add_rename).with("foo", "FOO")
      subject.update_product_renames("foo" => "FOO")
    end
  end

  describe ".check_repositories" do
    let(:repo) { 42 }

    before do
      allow(Yast::Pkg).to receive(:SourceGetCurrent).with(true).and_return([repo])
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(repo)
        .and_return("autorefresh" => true)
    end

    it "refreshes all repositories with autorefresh enabled" do
      expect(Yast::Pkg).to receive(:SourceGeneralData).with(repo)
        .and_return("autorefresh" => true)
      expect(Yast::Pkg).to receive(:SourceRefreshNow).with(repo).and_return(true)

      subject.check_repositories
    end

    it "returns true if all repositores refresh" do
      expect(Yast::Pkg).to receive(:SourceRefreshNow).with(repo).and_return(true)

      expect(subject.check_repositories).to eq(true)
    end

    context "a repository refresh fails" do
      before do
        expect(Yast::Pkg).to receive(:SourceRefreshNow).with(repo).and_return(false)
        allow(Registration::RepoStateStorage.instance).to receive(:add).with(repo, true)
        allow(Yast::Pkg).to receive(:SourceSetEnabled)
      end

      it "asks the user when a repository refresh fails" do
        expect(Yast::Popup).to receive(:ErrorAnyQuestion).and_return(false)

        subject.check_repositories
      end

      it "returns false if user select aborting the migration" do
        expect(Yast::Popup).to receive(:ErrorAnyQuestion).and_return(false)

        expect(subject.check_repositories).to eq(false)
      end

      it "disables the failed repo if user selects skipping it" do
        expect(Yast::Popup).to receive(:ErrorAnyQuestion).and_return(true)
        expect(Yast::Pkg).to receive(:SourceSetEnabled).with(repo, false)

        subject.check_repositories
      end

      it "returns true if user selects skipping the failed repo" do
        expect(Yast::Popup).to receive(:ErrorAnyQuestion).and_return(true)

        expect(subject.check_repositories).to eq(true)
      end

      it "remembers to re-enable the failed repo after migration" do
        allow(Yast::Popup).to receive(:ErrorAnyQuestion).and_return(true)
        expect(Registration::RepoStateStorage.instance).to receive(:add).with(repo, true)

        subject.check_repositories
      end
    end
  end

  describe ".remote_product" do
    let(:product) do
      {
        "name"            => "SLES",
        "arch"            => "x86_64",
        "version"         => "12.1-1.47",
        "version_version" => "12.1",
        "flavor"          => "DVD"
      }
    end

    it "converts a Hash into OpenStruct" do
      expect(subject.remote_product(product)).to be_an(OpenStruct)
    end

    it "includes the version release" do
      v = subject.remote_product(product).version
      expect(v).to include("-")
    end

    it "does not includes the version release if 'version_release' parameter is false" do
      v = subject.remote_product(product, version_release: false).version
      expect(v).to_not include("-")
    end
  end

  describe ".version_without_release" do
    let(:libzypp_product) do
      {
        "name"            => "SLESS",
        "arch"            => "x86_64",
        "version"         => "12.1-1.47",
        "version_version" => "12.1",
        "flavor"          => "DVD"
      }
    end
    let(:base_product) do
      instance_double(Y2Packager::Product, name: "SLES", version: "12.1-1.47", arch: "x86_64")
    end

    context "product can be found in libzypp stack" do

      it "returns version number without release" do
        expect(Yast::Pkg).to receive(:ResolvableProperties).and_return([libzypp_product])
        expect(subject.version_without_release(base_product))
          .to eq(libzypp_product["version_version"])
      end
    end

    context "product cannot be found in libzypp stack" do

      it "returns original version number at least" do
        expect(Yast::Pkg).to receive(:ResolvableProperties).and_return([])
        expect(subject.version_without_release(base_product)).to eq(libzypp_product["version"])
      end
    end
  end

end
