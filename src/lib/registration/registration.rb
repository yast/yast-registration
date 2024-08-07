# ------------------------------------------------------------------------------
# Copyright (c) 2014 SUSE LLC
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

require "ostruct"
require "yast"
require "y2packager/new_repository_setup"
require "suse/connect"
require "registration/connect_helpers"
require "registration/finish_dialog"

require "registration/addon"
require "registration/helpers"
require "registration/sw_mgmt"
require "registration/storage"
require "registration/ssl_certificate"

Yast.import "Installation"
Yast.import "ProductFeatures"
Yast.import "Mode"
Yast.import "Stage"

module Registration
  class Registration
    include Yast::Logger

    attr_accessor :url

    def initialize(url = nil)
      @url = url
    end

    def register(email, reg_code, distro_target)
      settings = connect_params(
        token: reg_code,
        email: email
      )

      log.info "Announcing system with distro_target: #{distro_target}"
      login = ""
      password = ""
      ConnectHelpers.catch_registration_errors do
        login, password = SUSE::Connect::YaST.announce_system(settings, distro_target)
      end
      log.info "Global SCC credentials (username): #{login}"

      # write the global credentials
      SUSE::Connect::YaST.create_credentials_file(login, password)

      # when managing a system in chroot copy the credentials to the target system
      if Yast::WFM.scr_chrooted?
        target_path = File.join(Yast::Installation.destdir, self.class.credentials_path)
        ::FileUtils.cp(self.class.credentials_path, target_path)
        ::Registration::FinishDialog.new.run("Write")
      end
    end

    def register_product(product, email = nil)
      service_for_product(product) do |product_ident, params|
        log_product = product.dup
        log_product["reg_code"] = "[FILTERED]" if log_product["reg_code"]
        log.info "Registering product: #{log_product}"

        service = SUSE::Connect::YaST.activate_product(product_ident, params, email)
        log.info "Register product result: #{service}"
        # remember the new service, might be useful later
        Y2Packager::NewRepositorySetup.instance.add_service(service.name)
        set_registered(product_ident)

        renames = collect_renames([service.product])
        SwMgmt.update_product_renames(renames)

        service
      end
    end

    def upgrade_product(product)
      service_for_product(product) do |product_ident, params|
        log.info "Upgrading product: #{product}"
        service = SUSE::Connect::YaST.upgrade_product(product_ident, params)
        log.info "Upgrade product result: #{service}"
        # remember the new service to not accidentally delete it as an old service
        Y2Packager::NewRepositorySetup.instance.add_service(service.name)
        # skip loading the remote addons in offline upgrade, there is a confusion
        # between installed and the upgraded product, moreover we do not need the
        # addons list at all
        set_registered(product_ident) unless Yast::Stage.initial

        renames = collect_renames([service.product])
        SwMgmt.update_product_renames(renames)

        service
      end
    end

    # downgrade product registration
    # used when restoring the original registration after aborted migration
    # @param [Hash] product libzypp product to which the registration should be downgraded
    def downgrade_product(product)
      service_for_product(product) do |product_ident, params|
        log.info "Downgrading product: #{product}"
        service = SUSE::Connect::YaST.downgrade_product(product_ident, params)
        log.info "Downgrade product result: #{service}"

        service
      end
    end

    # synchronize the registered products on the server with the local installed products
    # (removes all registrered products on the server which are not installed in the system)
    # @param [Array<Hash>] products list of installed libzypp products
    def synchronize_products(products)
      remote_products = products.map do |product|
        OpenStruct.new(
          arch:         product["arch"],
          identifier:   product["name"],
          version:      product["version_version"],
          release_type: product["release_type"]
        )
      end
      log.info "Synchronizing products: #{remote_products}"
      SUSE::Connect::YaST.synchronize(remote_products, connect_params)
    end

    # @param [String] target_distro new target distribution
    # @return [OpenStruct] SCC response
    def update_system(target_distro = nil)
      log.info "Updating the system, new target distribution: #{target_distro}"
      ret = SUSE::Connect::YaST.update_system(connect_params, target_distro)
      log.info "Update result: #{ret}"
      ret
    end

    # Get the list of addons
    #
    # @return [Array<Addon>] List of addons, empty if no base product is found
    def get_addon_list
      # extensions for base product
      base_product = if Yast::Mode.update
        ::Registration::SwMgmt.installed_base_product
      else
        ::Registration::SwMgmt.base_product_to_register
      end

      if !base_product
        log.warn "No base product, skipping addons"
        return []
      end

      log.info "Reading available addons for product: #{base_product["name"]}"

      # base_product_to_register returns "version_version" for the version
      # whereas installed_base_product returns "version_release".
      # SCC needs in this case the version without the release.
      remote_product = SwMgmt.remote_product(base_product, version_release: false)
      addons = SUSE::Connect::YaST.show_product(remote_product, connect_params).extensions || []
      addons.each { |a| log.info "Found available addon: #{a.inspect}" }

      renames = collect_renames(addons)
      ::Registration::SwMgmt.update_product_renames(renames)

      # ignore the base product "addon"
      addons.reject { |a| a.identifier == base_product["name"] }
    end

    def activated_products
      return [] unless Registration.is_registered?

      log.info "Reading activated products..."
      activated = SUSE::Connect::YaST.status(connect_params).activated_products || []
      log.info "Activated products: #{activated.map(&:identifier)}"
      activated
    end

    # get the list of migration products
    # @param [Array<SUSE::Connect::Remote::Product>] installed_products
    # @return [Array<Array<SUSE::Connect::Remote::Product>>] list of possible migrations,
    #   each migration contains a list of target products
    def migration_products(installed_products)
      log.info "Loading migration products for: #{installed_products}"
      migrations = []

      ConnectHelpers.catch_registration_errors do
        migrations = SUSE::Connect::YaST.system_migrations(installed_products, connect_params)
      end

      log.info "Received system migrations: #{migrations}"
      migrations
    end

    def offline_migration_products(installed_products, target_base_product)
      log.info "Offline migration for: #{target_base_product}."
      migration_paths = []
      ConnectHelpers.catch_registration_errors(show_update_hint: true) do
        migration_paths = SUSE::Connect::YaST
          .system_offline_migrations(installed_products,
            target_base_product, connect_params)
      end

      log.info "Received possible migrations paths: #{migration_paths}"
      migration_paths
    end

    # Get the list of installer updates for self_update_id and self_update_version
    # (the fallback version is read from the /etc/os-release file).
    #
    # @return [Array<String>] List of URLs of updates repositories.
    #
    # @see SwMgmt.installer_update_base_product
    # @see SUSE::Connect::Yast.list_installer_updates
    def get_updates_list
      id = Yast::ProductFeatures.GetStringFeature("globals", "self_update_id")
      return [] if id.empty?

      version = Yast::ProductFeatures.GetStringFeature("globals", "self_update_version")
      version = Yast::OSRelease.ReleaseVersion if version.empty?
      product = SwMgmt.installer_update_base_product(id, version)

      log.info "Reading available installer updates for product: #{product}"
      remote_product = SwMgmt.remote_product(product)
      updates = SUSE::Connect::YaST.list_installer_updates(remote_product, connect_params)

      log.info "Installer updates for '#{product["name"]}' are available at '#{updates}'"
      updates
    end

    # Full path to the SCC credentials file.
    def self.credentials_path
      SUSE::Connect::YaST::GLOBAL_CREDENTIALS_FILE
    end

    def self.is_registered?
      # just a simple file check without connection to SCC
      File.exist?(credentials_path)
    end

    # Whether the (re)registration is allowed
    #
    # The system can be (re)registered only
    #
    #  * when not registered yet, or
    #  * running in normal mode, or
    #  * during the firstboot stage
    #
    # @return [Boolean] true if system is not registered yet;
    #                   true when running in normal mode or firstboot stage;
    #                   false otherwise
    def self.allowed?
      # Always true if system is not registered yet
      return true unless Registration.is_registered?

      # System can be registered again only in normal mode or firstboot stage
      return true if Yast::Mode.normal || Yast::Stage.firstboot

      false
    end

  private

    def set_registered(remote_product)
      addon = Addon.find_all(self).find do |a|
        a.matches_remote_product?(remote_product)
      end

      return unless addon

      log.info "Marking addon #{addon.identifier}-#{addon.version} as registered"
      addon.registered
    end

    def service_for_product(product, &block)
      remote_product = if product.is_a?(Hash)
        SwMgmt.remote_product(product, version_release: false)
      else
        product
      end

      log.info "Using product: #{remote_product}"

      params = connect_params

      # use product specific reg. code (e.g. for addons)
      params[:token] = product["reg_code"] if product.is_a?(Hash) && product["reg_code"]

      product_service = block.call(remote_product, params)
      log.info "registration result: #{product_service}"
      update_services(product_service) if product_service

      product_service
    end

    # add/remove services for the registered product
    def update_services(product_service)
      old_service = product_service.obsoleted_service_name
      # sanity check
      # old_service comes from SCC. So it could be that we have already removed
      # this service from the system meanwhile --> checking first.
      if old_service && !old_service.empty? && old_service != product_service.name &&
          ::Registration::SwMgmt.service_installed?(old_service)
        log.info "Found obsoleted service: #{old_service}"
        ::Registration::SwMgmt.remove_service(old_service)
      end

      # read the global credentials
      credentials = SUSE::Connect::YaST.credentials(
        File.join(self.class.credentials_path)
      )
      ::Registration::SwMgmt.add_service(product_service, credentials)
    end

    # returns SSL verify callback
    def verify_callback
      lambda do |verify_ok, context|

        # we cannot raise an exception with details here (all exceptions in
        # verify_callback are caught and ignored), we need to store the error
        # details in a global instance
        store_ssl_error(context) unless verify_ok

        verify_ok
      rescue StandardError => e
        log.error "Exception in SSL verify callback: #{e.class}: #{e.message} : #{e.backtrace}"
        # the exception will be ignored, but reraise anyway...
        raise e

      end
    end

    def store_ssl_error(context)
      log.error "SSL verification failed: #{context.error}: #{context.error_string}"
      Storage::SSLErrors.instance.ssl_error_code = context.error
      Storage::SSLErrors.instance.ssl_error_msg = context.error_string
      Storage::SSLErrors.instance.ssl_failed_cert =
        context.current_cert ? SslCertificate.load(context.current_cert) : nil
    end

    def connect_params(params = {})
      default_params = {
        language:        ::Registration::Helpers.http_language,
        debug:           ENV["SCCDEBUG"],
        verbose:         ENV["Y2DEBUG"] == "1",
        # pass a verify_callback to get details about failed SSL verification
        verify_callback: verify_callback
      }

      if @url
        log.info "Using custom registration URL: #{@url.inspect}"
        default_params[:url] = @url
      end

      if Helpers.insecure_registration
        log.warn "SSL certificate check disabled via reg_ssl boot parameter"
        default_params[:insecure] = true
      end

      default_params.merge(params)
    end

    # collect product renames
    # @param products [Array<SUSE::Connect::Remote::Product>] remote products received from SCC
    # @return [Hash] hash with product renames: { old_name => new_name }
    def collect_renames(products)
      renames = {}

      products.each do |product|
        if product.former_identifier && product.identifier != product.former_identifier
          renames[product.former_identifier] = product.identifier
        end
      end

      log.info "Collected product renames: #{renames}"

      renames
    end
  end
end
