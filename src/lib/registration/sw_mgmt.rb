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

require "registration/exceptions"
require "registration/helpers"

module Registration
  Yast.import "Mode"
  Yast.import "Pkg"
  Yast.import "PackageLock"
  Yast.import "Installation"
  Yast.import "PackageCallbacksInit"

  class SwMgmt
    include Yast
    include Yast::Logger
    extend Yast::I18n

    textdomain "registration"

    ZYPP_DIR = "/etc/zypp"

    def self.init
      # false = do not allow continuing without the libzypp lock
      lock = PackageLock.Connect(false)
      return false unless lock["connected"]

      # display progress when refreshing repositories
      PackageCallbacksInit.InitPackageCallbacks
      Pkg.TargetInitialize(Installation.destdir)
      Pkg.TargetLoad
      Pkg.SourceRestore
    end

    # during installation /etc/zypp directory is not writable (mounted on
    # a read-only file system), the workaround is to copy the whole directory
    # structure into a writable temporary directory and override the original
    # location by "mount -o bind"
    def self.zypp_config_writable!
      return if !(Mode.installation || Mode.update) || File.writable?(ZYPP_DIR)

      log.info "Copying libzypp config to a writable place"

      # create writable zypp directory structure in /tmp
      tmpdir = Dir.mktmpdir

      log.info "Copying #{ZYPP_DIR} to #{tmpdir} ..."
      ::FileUtils.cp_r ZYPP_DIR, tmpdir

      log.info "Mounting #{tmpdir} to #{ZYPP_DIR}"
      `mount -o bind #{tmpdir}/zypp #{ZYPP_DIR}`
    end

    def self.find_base_product
      # during installation the products are :selected,
      # on a running system the products are :installed
      # during upgrade use the newer selected product (same as in installation)
      products = Pkg.ResolvableProperties("", :product, "").find_all do |p|
        if Mode.normal
          # in installed system the base product has valid type
          p["status"] == :installed && p["type"] == "base"
        else
          # however during installation it's not set yet
          # but the base product comes from the first repository
          p["status"] == :selected && p["source"] == 0
        end
      end

      log.debug "Found base products: #{products}"
      log.info "Found base products: #{products.map{|p| p["name"]}}"
      log.warn "More than one base product found!" if products.size > 1

      products.first
    end

    def self.base_product_to_register
      # just for debugging:
      # return {"name" => "SLES", "arch" => "x86_64", "version" => "12",
      #   "release_type" => "DVD"
      # }

      base_product = find_base_product

      # filter out not needed data
      product_info = {
        "name"         => base_product["name"],
        "arch"         => base_product["arch"],
        "version"      => ::Registration::Helpers.base_version(base_product["version"]),
        "release_type" => base_product["flavor"]
      }

      log.info("Base product to register: #{product_info}")

      product_info
    end

    # add the services to libzypp and load (refresh) them
    def self.add_services(product_services, credentials)
      # save repositories before refreshing added services (otherwise
      # pkg-bindings will treat them as removed by the service refresh and
      # unload them)
      if !Pkg.SourceSaveAll
        # error message
        raise ::Registration::PkgError, N_("Saving repository configuration failed.")
      end

      # services for registered products
      product_services.map(&:sources).flatten.each do |source|
        log.info "Adding service #{source.name.inspect} (#{source.url})"

        credentials_file = Helpers.credentials_from_url(source.url)

        if credentials_file
          # TODO FIXME: SCC currenly does not return credentials for the service,
          # just reuse the global credentials and save to a different file
          service_credentials = credentials.dup
          service_credentials.file = credentials_file
          service_credentials.write
        end

        # add a new service or update the existing service
        if Pkg.ServiceAliases.include?(source.name)
          log.info "Updating existing service: #{source.name}"
          if !Pkg.ServiceSet(source.name, {
                "alias" => source.name,
                "name" => source.name,
                "url" => source.url.to_s,
                "enabled" => true,
                "autorefresh" => true,
              })

            ## error message
            raise ::Registration::ServiceError.new(N_("Updating service '%s' failed."), source.name)
          end
        else
          log.info "Adding new service: #{source.name}"
          if !Pkg.ServiceAdd(source.name, source.url.to_s)
            # error message
            raise ::Registration::ServiceError.new(N_("Adding service '%s' failed."), source.name)
          end
        end

        # refresh works only for saved services
        if !Pkg.ServiceSave(source.name)
          # error message
          raise ::Registration::ServiceError.new(N_("Saving service '%s' failed."), source.name)
        end

        if !Pkg.ServiceRefresh(source.name)
          # error message
          raise ::Registration::ServiceError.new(N_("Refreshing service '%s' failed."), source.name)
        end
      end
    ensure
      Pkg.SourceSaveAll
    end

    # get list of repositories belonging to registered services
    # @param product_services [Array<SUSE::Connect::Service>] added services
    # @param only_updates [Boolean] return only update repositories
    # @return [Array<Hash>] list of repositories
    def self.service_repos(product_services, only_updates: false)
      repo_data = Pkg.SourceGetCurrent(false).map do |repo|
        data = Pkg.SourceGeneralData(repo)
        data["SrcId"] = repo
        data
      end

      service_names = product_services.map(&:services).flatten.map(&:name)
      log.info "Added services: #{service_names.inspect}"

      # select only repositories belonging to the product services
      repos = repo_data.select{|repo| service_names.include?(repo["service"])}
      log.info "Service repositories: #{repos}"

      if only_updates
        # leave only update repositories
        repos.select!{|repo| repo["is_update_repo"]}
        log.info "Found update repositories: #{repos}"
      end

      repos
    end

    # Set repository state (enabled/disabled)
    # @param repos [Array<Hash>] list of repositories
    # @param repos [Boolean] true = enable, false = disable, nil = no change
    # @return [void]
    def self.set_repos_state(repos, enabled)
      # keep the defaults when not defined
      return if enabled.nil?

      repos.each do |repo|
        if repo["enabled"] != enabled
          log.info "Changing repository state: #{repo["name"]} enabled: #{enabled}"
          Pkg.SourceSetEnabled(repo["SrcId"], enabled)
        end
      end
    end

  end
end

