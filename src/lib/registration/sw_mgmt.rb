# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2014 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------
#
#

require "yast"

require "tmpdir"
require "fileutils"
require "shellwords"
require "ostruct"

require "registration/exceptions"
require "registration/helpers"
require "registration/url_helpers"
require "registration/repo_state"

require "packager/product_patterns"
require "y2packager/product_reader"

module Registration
  Yast.import "AddOnProduct"
  Yast.import "Mode"
  Yast.import "Stage"
  Yast.import "Pkg"
  Yast.import "Report"
  Yast.import "PackageLock"
  Yast.import "Installation"
  Yast.import "PackageCallbacks"
  Yast.import "Popup"
  Yast.import "Product"

  class SwMgmt
    include Yast
    include Yast::Logger
    extend Yast::I18n

    textdomain "registration"

    ZYPP_DIR = "/etc/zypp".freeze

    FAKE_BASE_PRODUCT = { "name" => "SLES", "arch" => "x86_64", "version" => "12-0",
      "flavor" => "DVD", "version_version" => "12", "register_release" => "",
      "register_target" => "sle-12-x86_64" }.freeze

    OEM_DIR = "/var/lib/suseRegister/OEM".freeze

    # initialize the package management
    # @param [Boolean] load_packages load also the available packages from the repositories
    def self.init(load_packages = false)
      # false = do not allow continuing without the libzypp lock
      lock = PackageLock.Connect(false)
      # User would like to abort
      raise_pkg_exception(PkgAborted) if lock["aborted"]
      # locking has failed
      raise_pkg_exception unless lock["connected"]

      # display progress when refreshing repositories
      PackageCallbacks.InitPackageCallbacks

      raise_pkg_exception unless init_target(Installation.destdir)
      raise_pkg_exception unless Pkg.TargetLoad
      raise_pkg_exception(SourceRestoreError) unless Pkg.SourceRestore

      raise_pkg_exception if load_packages && !Pkg.SourceLoad
    end

    # try refreshing all enabled repositories with autorefresh enabled
    # and report repositories which fail, ask the user to disable them or to abort
    # @return [Boolean] true = migration can continue, false = abort migration
    def self.check_repositories
      # only enabled repositories
      repos = Pkg.SourceGetCurrent(true)

      repos.each do |repo|
        data = Pkg.SourceGeneralData(repo)
        # skip repositories which have autorefresh disabled
        next unless data["autorefresh"]

        log.info "Refreshing repository #{data["alias"].inspect}"
        next if Pkg.SourceRefreshNow(repo)

        # TRANSLATORS: error popup, %s is a repository name, the popup is displayed
        # when a migration repository cannot be accessed, there are [Skip]
        # and [Abort] buttons displayed below the question
        question = _("Repository '%s'\ncannot be loaded.\n\n"\
            "Skip the repository or abort?") % data["name"]
        ret = Popup.ErrorAnyQuestion(Label.ErrorMsg, question, Label.SkipButton,
          Label.AbortButton, :focus_yes)

        log.info "Abort online migration: #{ret}"
        return false unless ret

        # disable the repository
        log.info "Disabling repository #{data["alias"].inspect}"
        Pkg.SourceSetEnabled(repo, false)

        # make sure the repository is enabled again after migration
        RepoStateStorage.instance.add(repo, true)
      end

      true
    end

    # Prepare a pkg-binding product info hash
    #
    # If there is available products in the media, the first of them will be used as a template,
    # keeping the self_update_id as the product name, since it is expected that all of them use the
    # same version and arch.
    #
    # @param self_update_id [String] product name to be used for get the installer updates
    # @param self_update_version [String] product version to be used for get the installer updates
    #
    # @return [Hash,nil] with pkg-binding format; nil if the given self_update_id is empty or there
    #                    is no base product available
    def self.installer_update_base_product(self_update_id, self_update_version)
      base_product = Y2Packager::Product.available_base_products.first

      name = self_update_id.to_s
      version = base_product ? version_without_release(base_product) : self_update_version.to_s

      return if name.empty? || version.empty?

      product_info = {
        "name"         => self_update_id,
        "version"      => version,
        "arch"         => base_product ? base_product.arch : Yast::Arch.architecture,
        "release_type" => nil
      }

      log.info("Base product for installer update: #{product_info}")

      product_info
    end

    def self.find_base_product
      # FIXME: refactor the code to use Y2Packager::Product

      # just for debugging:
      return FAKE_BASE_PRODUCT if ENV["FAKE_BASE_PRODUCT"]

      # use the selected product if a product has been already selected
      selected = product_selected? if Stage.initial
      installed = product_installed? if Stage.initial

      # list of products defined by the "system-installation()" provides
      system_products = Y2Packager::ProductReader.installation_package_mapping.keys
      log.info("Found system-installation() products: #{system_products.inspect}")

      # during installation the products are :selected,
      # on a running system the products are :installed
      # during upgrade use the newer selected product (same as in installation)
      # The base product must be marked by the "system-installation()" provides
      # by some package.
      products = Pkg.ResolvableProperties("", :product, "").find_all do |p|
        if Stage.initial && !system_products.include?(p["name"])
          log.info("Skipping product #{p["name"].inspect}, no system-installation() provides")
          next false
        end

        evaluate_product(p, selected, installed)
      end

      log.debug "Found base products: #{products}"
      log.info "Found base products: #{products.map { |p| p["name"] }}"
      log.warn "More than one base product found!" if products.size > 1

      products.first
    end

    # Evaluate the product if it is a base product depending on the current
    # system status.
    # @param p [Hash] the product from pkg-bindings
    # @param selected [Boolean,nil] is any product selected?
    # @param installed [Boolean,nil] is any product istalled?
    # @return [Boolean] true if it is a base product
    def self.evaluate_product(p, selected, installed)
      if Stage.initial && Mode.auto
        Yast.import "AutoinstFunctions"
        # note: AutoinstFunctions.selected_product should never be nil when
        # AY let it pass here
        return false unless AutoinstFunctions.selected_product
        p["name"] == AutoinstFunctions.selected_product.name
      elsif Stage.initial && !Mode.update
        # during installation the ["type"] value is not valid yet yet
        # (the base product is determined by /etc/products.d/baseproduct symlink)
        # use the selected or available product
        p["status"] == (selected ? :selected : :available)
      elsif Stage.initial
        # during upgrade it depends on whether target is already initialized,
        # use the product from the medium for the self-update step
        # (during upgrade the installed product might me already selected for removal)
        if installed
          (p["status"] == :installed || p["status"] == :removed) && p["type"] == "base"
        elsif selected
          p["status"] == :selected
        else
          p["status"] == :available
        end
      else
        # in installed system or at upgrade the base product has valid type
        (p["status"] == :installed || p["status"] == :removed) && p["type"] == "base"
      end
    end

    private_class_method :evaluate_product

    # Any product selected to install?
    # @return [Boolean] true if at least one product is selected to install
    def self.product_selected?
      Pkg.ResolvableProperties("", :product, "").any? { |p| p["status"] == :selected }
    end

    # Any product installed? (e.g. during upgrade)
    # @return [Boolean] true if at least one product is installed
    def self.product_installed?
      Pkg.ResolvableProperties("", :product, "").any? do |p|
        p["status"] == :installed || p["status"] == :removed
      end
    end

    def self.installed_products
      # just for testing/debugging
      return [FAKE_BASE_PRODUCT] if ENV["FAKE_BASE_PRODUCT"]

      all_products = Pkg.ResolvableProperties("", :product, "")
      log.info("Evaluating products: #{all_products}")

      products = all_products.select do |p|
        # installed or installed marked for removal (at upgrade)
        p["status"] == :installed || p["status"] == :removed
      end

      log.info "Found installed products: #{products.map { |p| p["name"] }}"
      products
    end

    # Convert a libzypp Product Hash to a SUSE::Connect::Remote::Product object
    #
    # @param product [Hash] product Hash obtained from pkg-bindings
    # @return [OpenStruct] a remote product representation
    def self.remote_product(product, version_release: true)
      # default value if it does not exist
      product["version_version"] ||= product["version"]

      OpenStruct.new(
        arch:         product["arch"],
        identifier:   product["name"],
        # the "version_version" key does not contain the release number,
        # e.g. if "version" is "11.4-1.109" then "version_version" is just "11.4"
        version:      version_release ? product["version"] : product["version_version"],
        release_type: product["release_type"]
      )
    end

    # remove relase string from version. E.g.: "15-0" --> "15"
    # @param product [Y2Packager::Product] product
    # @return [String] version
    def self.version_without_release(product)
      pkg_product = Yast::Pkg.ResolvableProperties(product.name,
        :product, product.version).first
      pkg_product ? pkg_product["version_version"] : product.version
    end

    # create UI label for a base product
    # @param base_product [Hash] Product (hash from pkg-bindings)
    # @return [String] UI Label
    def self.product_label(base_product)
      base_product["display_name"] ||
        base_product["short_name"] ||
        base_product["name"] ||
        _("Unknown product")
    end

    def self.base_product_to_register
      # use FAKE_BASE_PRODUCT just for debugging
      base_product = ENV["FAKE_BASE_PRODUCT"] ? FAKE_BASE_PRODUCT : find_base_product

      return unless base_product

      # filter out not needed data
      product_info = {
        "name"         => base_product["name"],
        "arch"         => base_product["arch"],
        "version"      => base_product["version_version"],
        "release_type" => get_release_type(base_product)
      }

      log.info("Base product to register: #{product_info}")

      product_info
    end

    # add the services to libzypp and load (refresh) them
    def self.add_service(product_service, credentials)
      # save repositories before refreshing added services (otherwise
      # pkg-bindings will treat them as removed by the service refresh and
      # unload them)
      if !Pkg.SourceSaveAll
        # error message
        raise ::Registration::PkgError, N_("Saving repository configuration failed.")
      end

      # services for registered products
      log.info "Adding service #{product_service.name.inspect} (#{product_service.url})"

      credentials_file = UrlHelpers.credentials_from_url(product_service.url)

      if credentials_file
        if Mode.update
          # at update libzypp is already switched to /mnt target,
          # update the path accordingly
          credentials_file = File.join(Installation.destdir,
            ::SUSE::Connect::YaST::DEFAULT_CREDENTIALS_DIR,
            credentials_file)
          log.info "Using #{credentials_file} credentials path in update mode"
        end
        # SCC uses the same credentials for all services, just save them to
        # a different file
        SUSE::Connect::YaST.create_credentials_file(credentials.username,
          credentials.password, credentials_file)
      end

      service_name = product_service.name

      # add a new service or update the existing service
      if Pkg.ServiceAliases.include?(service_name)
        log.info "Updating existing service: #{service_name}"
        if !Pkg.ServiceSet(service_name,
          "alias"       => service_name,
          "name"        => service_name,
          "url"         => product_service.url.to_s,
          "enabled"     => true,
          "autorefresh" => true)

          ## error message
          raise ::Registration::ServiceError.new(N_("Updating service '%s' failed."), service_name)
        end
      else
        log.info "Adding new service: #{service_name}"
        if !Pkg.ServiceAdd(service_name, product_service.url.to_s)
          # error message
          raise ::Registration::ServiceError.new(N_("Adding service '%s' failed."), service_name)
        end

        if !Pkg.ServiceSet(service_name, "autorefresh" => true)
          # error message
          raise ::Registration::ServiceError.new(N_("Updating service '%s' failed."), service_name)
        end
      end

      # refresh works only for saved services
      if !Pkg.ServiceSave(service_name)
        # error message
        raise ::Registration::ServiceError.new(N_("Saving service '%s' failed."), service_name)
      end

      # Force refreshing due timing issues (bnc#967828)
      if !Pkg.ServiceForceRefresh(service_name)
        # error message
        raise ::Registration::ServiceError.new(N_("Refreshing service '%s' failed."), service_name)
      end
    ensure
      Pkg.SourceSaveAll
    end

    # remove a libzypp service and save the repository configuration
    # @param [String] name name of the service to remove
    def self.remove_service(name)
      log.info "Removing service #{name}"

      if Pkg.ServiceDelete(name) && !Pkg.SourceSaveAll
        # error message
        raise ::Registration::PkgError, N_("Saving repository configuration failed.")
      end
    end

    # get list of repositories belonging to registered services
    # @param product_service [SUSE::Connect::Remote::Service] added service
    # @param only_updates [Boolean] return only update repositories
    # @return [Array<Hash>] list of repositories
    def self.service_repos(product_service, only_updates: false)
      repo_data = Pkg.SourceGetCurrent(false).map { |repo| repository_data(repo) }

      service_name = product_service.name
      log.info "Service name: #{service_name.inspect}"

      # select only repositories belonging to the product services
      repos = repo_data.select { |repo| service_name == repo["service"] }
      log.info "Service repositories: #{repos}"

      if only_updates
        # leave only update repositories
        repos.select! { |repo| repo["is_update_repo"] }
        log.info "Found update repositories: #{repos}"
      end

      repos
    end

    # get repository data
    # @param [Fixnum] repo repository ID
    # @return [Hash] repository properties, including the repository ID ("SrcId" key)
    def self.repository_data(repo)
      data = Pkg.SourceGeneralData(repo)
      data["SrcId"] = repo
      data
    end

    # Set repository state (enabled/disabled)
    # The original repository state is saved to RepoStateStorage to restore
    # the original state later.
    # @param repos [Array<Hash>] list of repositories
    # @param enabled [Boolean] true = enable, false = disable, nil = no change
    # @return [void]
    def self.set_repos_state(repos, enabled)
      # keep the defaults when not defined
      return if enabled.nil?

      repos.each do |repo|
        next if repo["enabled"] == enabled

        # remember the original state
        RepoStateStorage.instance.add(repo["SrcId"], repo["enabled"])

        log.info "Changing repository state: #{repo["name"]} enabled: #{enabled}"
        Pkg.SourceSetEnabled(repo["SrcId"], enabled)
      end
    end

    # copy old NCC/SCC credentials from the old installation to new SCC credentials
    # the files are copied to the root of the current system (/), at installation
    # the credentials are copied to the target (/mnt) at the beginning of the
    # installation (in the inst_kickoff.rb client)
    def self.copy_old_credentials(source_dir)
      log.info "Searching registration credentials in #{source_dir}..."

      dir = SUSE::Connect::YaST::DEFAULT_CREDENTIALS_DIR
      # create the target directory if missing
      if !File.exist?(dir)
        log.info "Creating directory #{dir}"
        ::FileUtils.mkdir_p(dir)
      end

      # if the system contains both NCC and SCC credentials then the SCC ones
      # should be preferred (bsc#1096813)
      # take advantage that "NCCcredentials" is alphabetically before
      # "SCCcredentials" so it is enough to just sort the files and then the
      # SCC credentials will simply overwrite the NCC credentials
      Dir[File.join(source_dir, dir, "*")].sort.each do |path|
        # skip non-files
        next unless File.file?(path)

        # check for the NCC credentials, we need to save them as the SCC credentials
        new_path = if File.basename(path) == "NCCcredentials"
          SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE
        else
          File.join(dir, File.basename(path))
        end

        copy_old_credentials_file(path, new_path)
      end
    end

    private_class_method def self.copy_old_credentials_file(file, new_file)
      log.info "Copying the old credentials from previous installation"
      log.info "Copying #{file} to #{new_file}"

      # SMT uses extra ACL permissions, make sure they are kept in the copied file,
      # (use "cp -a ", ::FileUtils.cp(..., preserve: true) cannot be used as it preserves only
      # the traditional Unix file permissions, the extended ACLs are NOT copied!)
      `cp -a #{Shellwords.escape(file)} #{Shellwords.escape(new_file)}`

      credentials = SUSE::Connect::YaST.credentials(new_file)
      log.info "Using previous credentials (username): #{credentials.username}"
    rescue SUSE::Connect::MalformedSccCredentialsFile => e
      log.warn "Cannot parse the credentials file: #{e.inspect}"
    end

    def self.find_addon_updates(addons)
      log.info "Available addons: #{addons.map(&:identifier)}"

      products = Pkg.ResolvableProperties("", :product, "")

      installed_addons = products.select do |product|
        (product["status"] == :installed || product["status"] == :removed) &&
          product["type"] != "base"
      end

      product_names = installed_addons.map { |a| "#{a["name"]}-#{a["version"]}-#{a["release"]}" }
      log.info "Installed addons: #{product_names}"

      ret = addons.select do |addon|
        installed_addons.any? do |installed_addon|
          addon.updates_addon?(installed_addon)
        end
      end

      log.info "Found addons to update: #{ret.map(&:identifier)}"
      ret
    end

    # update the static defaults in AddOnProduct module
    def self.update_product_renames(renames)
      renames.each do |old_name, new_name|
        AddOnProduct.add_rename(old_name, new_name)
      end
    end

    # a helper method for iterating over repositories
    # @param repo_aliases [Array<String>] list of repository aliases
    # @param block block evaluated for each found repository
    private_class_method def self.each_repo(repo_aliases, &block)
      all_repos = Pkg.SourceGetCurrent(false)

      repo_aliases.each do |repo_alias|
        # find the repository with the alias
        repository = all_repos.find do |repo|
          Pkg.SourceGeneralData(repo)["alias"] == repo_alias
        end

        if repository
          block.call(repository)
        else
          log.warn "Repository '#{repo_alias}' was not found, skipping"
        end
      end
    end

    # select products for new added extensions/modules
    #
    # @param addon_services [Array<SUSE::Connect::Remote::Service] List of services
    #   If it is not specified, it falls back to {Registration::Storage::Cache#addon_services}.
    # @return [Boolean] true on success
    def self.select_addon_products(addon_services = nil)
      addon_services ||= ::Registration::Storage::Cache.instance.addon_services
      log.info "New addon services: #{addon_services}"

      new_repos = addon_services.reduce([]) do |acc, service|
        acc.concat(::Registration::SwMgmt.service_repos(service))
      end

      return true if new_repos.empty?

      products = Pkg.ResolvableProperties("", :product, "")
      products.select! do |product|
        product["status"] == :available &&
          new_repos.any? { |new_repo| product["source"] == new_repo["SrcId"] }
      end
      products.map! { |product| product["name"] }

      log.info "Products to install: #{products}"

      ret = products.all? { |product| Pkg.ResolvableInstall(product, :product) }

      select_default_product_patterns unless Mode.update

      ret
    end

    # Select default product patterns
    def self.select_default_product_patterns
      # preselect the default product patterns (FATE#320199)
      # note: must be called *after* selecting the products
      product_patterns = ProductPatterns.new
      log.info "Selecting the default product patterns: #{product_patterns.names}"
      product_patterns.select
    end

    # select remote addons matching the product resolvables
    def self.select_product_addons(products, addons)
      addons.each do |addon|
        log.info "Found remote addon: #{addon.identifier}-#{addon.version}-#{addon.arch}"
      end

      # select a remote addon for each product
      products.each do |product|
        remote_addon = addons.find do |addon|
          product["name"] == addon.identifier &&
            product["version_version"] == addon.version &&
            product["arch"] == addon.arch
        end

        if remote_addon
          remote_addon.selected
        else
          product_label = "#{product["display_name"]} (#{product["name"]}" \
            "-#{product["version_version"]}-#{product["arch"]})"

          # TRANSLATORS: %s is a product name
          Report.Error(_("Cannot find remote product %s.\n" \
                "The product cannot be registered.") % product_label)
        end
      end
    end

    # find the product resolvables from the specified repository
    def self.products_from_repo(repo_id)
      # TODO: only installed products??
      Pkg.ResolvableProperties("", :product, "").select do |product|
        product["source"] == repo_id
      end
    end

    def self.get_release_type(product)
      if product["product_line"]
        oem_file = File.join(OEM_DIR, product["product_line"])

        if File.exist?(oem_file)
          # read only the first line
          line = File.open(oem_file, &:readline)
          return line.chomp if line
        end
      end

      product["register_release"]
    end

    def self.raise_pkg_exception(klass = PkgError)
      raise klass, Pkg.LastError
    end

    # initialize the libzypp target
    # @param destdir [String] the target directory
    # @return [Boolean] true on sucess, false otherwise
    def self.init_target(destdir)
      if Stage.initial && Mode.update
        # at upgrade we need to override the target_distro otherwise libzypp
        # will use the old value from the upgraded system which might not
        # match the new target_distro from the media and might result in ignoring
        # service repositories (bsc#1094865)
        options = { "target_distro" => target_distribution }
        Pkg.TargetInitializeOptions(destdir, options)
      else
        Pkg.TargetInitialize(destdir)
      end
    end

    # get the target distribution for the new base product
    # @return [String] target distribution name or empty string if not found
    def self.target_distribution
      base_products = Product.FindBaseProducts

      # empty target distribution disables service compatibility check in case
      # the base product cannot be found
      target_distro = base_products ? base_products.first["register_target"] : ""
      log.info "Base product target distribution: #{target_distro.inspect}"

      target_distro
    end

    private_class_method :init_target, :target_distribution
  end
end
