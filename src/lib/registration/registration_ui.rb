# encoding: utf-8

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

require "yast"

require "registration/connect_helpers"
require "registration/registration"
require "registration/sw_mgmt"
require "registration/storage"
require "registration/ui/addon_reg_codes_dialog"

module Registration
  # Registration functions with errror handling, progress messages, etc...
  # This is a high level API above Registration::Registration class
  class RegistrationUI
    include Yast::Logger
    include Yast::UIShortcuts
    include Yast::I18n
    extend Yast::I18n

    # popup message
    CONTACTING_MESSAGE = N_("Contacting the Registration Server")

    def initialize(registration)
      textdomain "registration"
      @registration = registration

      Yast.import "Mode"
      Yast.import "Popup"
      Yast.import "Wizard"
      Yast.import "Mode"
    end

    # register the system and the base product
    # the registration parameters are read from Storage::InstallationOptions
    # @return [Array<Boolean, SUSE::Connect::Remote::Service>] array with two
    #   items: boolean (true on success), remote service (or nil)
    def register_system_and_base_product
      product_service = nil

      success = ConnectHelpers.catch_registration_errors do
        register_system if !Registration.is_registered?

        # then register the product(s)
        product_service = register_base_product
      end

      log.info "Registration suceeded: #{success}"
      [success, product_service]
    end

    # @return [Boolean] true on success
    def update_system
      updated = ConnectHelpers.catch_registration_errors(show_update_hint: true) do
        base_product = SwMgmt.find_base_product
        target_distro = base_product["register_target"]

        Yast::Popup.Feedback(
          _(CONTACTING_MESSAGE),
          # FIXME: reused an existing message due to text freeze
          # (later use a better text, it's system update actually...)
          _("Registering the System...")
        ) do
          registration.update_system(target_distro)
        end
      end

      if !updated
        log.info "System update failed, removing the credentials to register from scratch"
        Helpers.reset_registration_status
        UrlHelpers.reset_registration_url
        Storage::Cache.instance.upgrade_failed = true
      end

      updated
    end

    # update base product registration
    # @return [Boolean] true on success
    def update_base_product
      product_service = nil
      upgraded = ConnectHelpers.catch_registration_errors(show_update_hint: true) do
        # then register the product(s)
        base_product = SwMgmt.base_product_to_register
        product_service = Yast::Popup.Feedback(
          _(CONTACTING_MESSAGE),
          # updating base product registration, %s is a new base product name
          _("Updating to %s ...") % SwMgmt.product_label(
            SwMgmt.find_base_product)
        ) do
          registration.upgrade_product(base_product)
        end
      end

      if !upgraded
        log.info "Registration upgrade failed, removing the credentials to register from scratch"
        Helpers.reset_registration_status
      end

      [upgraded, product_service]
    end

    # @param [Array<Registration::Addon>] addons to update
    def update_addons(addons, enable_updates: true)
      # find addon updates
      addons_to_update = SwMgmt.find_addon_updates(addons)
      log.info "addons to update: #{addons_to_update.inspect}"

      failed_addons = addons_to_update.reject do |addon_to_update|
        update_addon(addon_to_update, enable_updates)
      end

      # install the new upgraded products
      SwMgmt.select_addon_products

      log.error "Failed addons: #{failed_addons}" unless failed_addons.empty?
      failed_addons
    end

    # downgrade product registration
    # @param [Hash] product libzypp product which registration will be downgraded
    # @return [Array<Boolean, OpenStruct>] a pair with success flag and the
    # registered remote service
    def downgrade_product(product)
      product_service = nil
      success = ConnectHelpers.catch_registration_errors do
        product_service = Yast::Popup.Feedback(
          _(CONTACTING_MESSAGE),
          # updating product registration, %s is a product name
          _("Updating to %s ...") % SwMgmt.product_label(product)
        ) do
          registration.downgrade_product(product)
        end
      end

      [success, product_service]
    end

    # synchronize the local products with the registration server
    # @param [Array<Hash>] products libzypp products to synchronize
    # @return [Boolean] true on success
    def synchronize_products(products)
      ConnectHelpers.catch_registration_errors do
        Yast::Popup.Feedback(
          _(CONTACTING_MESSAGE),
          # TRANSLATORS: progress label
          _("Synchronizing Products...")
        ) do
          registration.synchronize_products(products)
        end
      end
    end

    # load available addons from SCC server
    # the result is cached to avoid reloading when going back and forth in the
    # installation workflow
    # @return [Array<Registration::Addon>] available addons
    def get_available_addons
      Yast::Popup.Feedback(
        _(CONTACTING_MESSAGE),
        _("Loading Available Extensions and Modules...")) do
        Addon.find_all(registration)
      end
    end

    def disable_update_repos(product_service)
      update_repos = SwMgmt.service_repos(product_service, only_updates: true)
      log.info "Disabling #{update_repos.size} update repositories: #{update_repos}"
      SwMgmt.set_repos_state(update_repos, false)
    end

    def migration_products(products)
      Yast::Popup.Feedback(
        _(CONTACTING_MESSAGE),
        _("Loading Migration Products...")) do
        registration.migration_products(products)
      end
    end

    # Register the selected addons, asks for reg. codes if required, known_reg_codes
    # @param selected_addons [Array<Addon>] list of addons selected for registration,
    #   successfully registered addons are removed from the list
    # @param known_reg_codes [Hash] remembered reg. code, it's updated with the
    #   user entered values
    # @return [Symbol]
    def register_addons(selected_addons, known_reg_codes)
      # if registering only add-ons which do not need a reg. code (like SDK)
      # then simply start the registration
      if selected_addons.all?(&:free)
        Yast::Wizard.SetContents(
          # dialog title
          _("Register Extensions and Modules"),
          # display only the products which need a registration code
          Empty(),
          # help text
          _("<p>Extensions and Modules are being registered.</p>"),
          false,
          false
        )
        # when registration fails go back
        return register_selected_addons(selected_addons, known_reg_codes) ? :next : :back
      else
        loop do
          ret = UI::AddonRegCodesDialog.run(selected_addons, known_reg_codes)
          return ret unless ret == :next

          return :next if register_selected_addons(selected_addons, known_reg_codes)
        end
      end
    end

    def install_updates?
      # ask only at installation/update
      return true unless Yast::Mode.installation || Yast::Mode.update

      options = Storage::InstallationOptions.instance

      # not set yet?
      if options.install_updates.nil?
        # TRANSLATORS: updates popup question (1/2), multiline, max. ~60 chars/line
        msg = _("The registration server offers update repositories.\n\n")

        if Yast::Mode.installation
          # TRANSLATORS: updates popup question (2/2), multiline, max. ~60 chars/line
          msg += _("Would you like to enable these repositories during installation\n" \
              "in order to receive the latest updates?")
        else # Yast::Mode.update
          # TRANSLATORS: updates popup question (2/2), multiline, max. ~60 chars/line
          msg += _("Would you like to enable these repositories during upgrade\n" \
              "in order to receive the latest updates?")
        end

        options.install_updates = Yast::Popup.YesNo(msg)
      end

      options.install_updates
    end

    private

    attr_accessor :registration

    def register_system
      options = Storage::InstallationOptions.instance
      base_product = SwMgmt.find_base_product
      distro_target = base_product["register_target"]

      log.info "Registering system, distro_target: #{distro_target}"

      Yast::Popup.Feedback(_(CONTACTING_MESSAGE),
        _("Registering the System...")) do
        registration.register(options.email, options.reg_code, distro_target)
      end
    end

    # the credentials are read from Storage::InstallationOptions
    def register_base_product
      options = Storage::InstallationOptions.instance
      return if options.base_registered

      # then register the product(s)
      base_product = SwMgmt.find_base_product

      Yast::Popup.Feedback(_(CONTACTING_MESSAGE),
        _("Registering %s ...") % SwMgmt.product_label(base_product)
      ) do
        base_product_data = SwMgmt.base_product_to_register
        base_product_data["reg_code"] = options.reg_code
        registration.register_product(base_product_data, options.email)
      end
    end

    # register all selected addons
    def register_selected_addons(selected_addons, known_reg_codes)
      # create duplicate as array is modified in loop for registration order
      registration_order = selected_addons.clone

      product_succeed = registration_order.map do |product|
        registered = ConnectHelpers.catch_registration_errors(
          message_prefix: "#{product.label}\n") do
            register_selected_addon(product, known_reg_codes[product.identifier])
          end

        # remove from selected after successful registration
        if registered
          selected_addons.reject! { |selected| selected.identifier == product.identifier }
        end
        registered
      end

      !product_succeed.include?(false) # succeed only if noone failed
    end

    def register_selected_addon(product, reg_code)
      product_service = Yast::Popup.Feedback(
        _(CONTACTING_MESSAGE),
        # %s is name of given product
        _("Registering %s ...") % product.label) do
        product_data = {
          "name"     => product.identifier,
          "reg_code" => reg_code,
          "arch"     => product.arch,
          "version"  => product.version
        }

        registration.register_product(product_data)
      end

      # select repositories to use in installation (e.g. enable/disable Updates)
      select_repositories(product_service) if Yast::Mode.installation || Yast::Mode.update

      # remember the added service
      Storage::Cache.instance.addon_services << product_service

      # mark as registered
      product.registered
    end

    def select_repositories(product_service)
      # added update repositories
      updates = SwMgmt.service_repos(product_service, only_updates: true)
      log.info "Found update repositories: #{updates.size}"

      SwMgmt.set_repos_state(updates, install_updates?)
    end

    # update addon registration to a new version
    # @param [Registration::Addon] addon addon to update
    def update_addon(addon, enable_updates)
      ConnectHelpers.catch_registration_errors do
        # then register the product(s)
        product_service = Yast::Popup.Feedback(
          _(CONTACTING_MESSAGE),
          # updating registered addon/extension, %s is an extension name
          _("Updating to %s ...") % addon.label
        ) do
          # FIXME: unify with add-on upgrade in online migration
          registration.upgrade_product(SwMgmt.remote_product(addon.to_h))
        end

        Storage::Cache.instance.addon_services << product_service

        # select repositories to use in installation (e.g. enable/disable Updates)
        disable_update_repos(product_service) if !enable_updates
      end
    end
  end
end
