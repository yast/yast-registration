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

module Registration

  # Registration functions with errror handling, progress messages, etc...
  # This is a high level APi above Registration::Registration class
  class RegistrationUI
    include Yast::Logger
    include Yast::I18n
    extend Yast::I18n

    # popup message
    CONTACTING_MESSAGE = N_("Contacting the Registration Server")

    def initialize(registration)
      textdomain "registration"
      @registration = registration

      Yast.import "Popup"
    end

    # register the system and the base product
    # @return [Boolean] true on success
    # TODO FIXME: split to two separate parts
    def register_system_and_base_product(email, reg_code,
        register_base_product: true, disable_updates: false)

      success = ConnectHelpers.catch_registration_errors do
        base_product = SwMgmt.find_base_product

        if !Registration.is_registered?
          distro_target = base_product["register_target"]
          log.info "Registering system, distro_target: #{distro_target}"

          Yast::Popup.Feedback(_(CONTACTING_MESSAGE),
            _("Registering the System...")) do

            registration.register(email, reg_code, distro_target)
          end
        end

        if register_base_product
          # then register the product(s)
          product_service = Yast::Popup.Feedback(_(CONTACTING_MESSAGE),
            _("Registering %s ...") % SwMgmt.base_product_label(base_product)
          ) do

            base_product_data = SwMgmt.base_product_to_register
            base_product_data["reg_code"] = reg_code
            registration.register_product(base_product_data, email)
          end

          # select repositories to use in installation or update (e.g. enable/disable Updates)
          disable_update_repos(product_service) if disable_updates
        end
      end

      log.info "Registration suceeded: #{success}"
      success
    end


    # @parama [Boolean] enable_updates Enable or disable added update repositories
    # @return [Boolean] true on success
    def update_base_product(enable_updates: true)
      upgraded = ConnectHelpers.catch_registration_errors(show_update_hint: true) do
        # then register the product(s)
        base_product = SwMgmt.base_product_to_register
        product_service = Yast::Popup.Feedback(
          _(CONTACTING_MESSAGE),
          # updating base product registration, %s is a new base product name
          _("Updating to %s ...") % SwMgmt.base_product_label(
            SwMgmt.find_base_product)
        ) do
          registration.upgrade_product(base_product)
        end

        # select repositories to use in installation (e.g. enable/disable Updates)
        disable_update_repos(product_service) if !enable_updates
      end

      if !upgraded
        log.info "Registration upgrade failed, removing the credentials to register from scratch"
        Helpers.reset_registration_status
      end

      upgraded
    end

    def update_addons(addons, enable_updates: true)
      # find addon updates
      addons_to_update = SwMgmt.find_addon_updates(addons)

      failed_addons = addons_to_update.reject do |addon_to_update|
        ConnectHelpers.catch_registration_errors do
          # then register the product(s)
          product_service = Yast::Popup.Feedback(
            _(CONTACTING_MESSAGE),
            # updating registered addon/extension, %s is an extension name
            _("Updating to %s ...") % addon_to_update.label
          ) do
            registration.upgrade_product(addon_to_update)
          end

          Storage::Cache.instance.addon_services << product_service

          # select repositories to use in installation (e.g. enable/disable Updates)
          disable_update_repos(product_service) if !enable_updates
        end
      end

      # install the new upgraded products
      SwMgmt.select_addon_products

      log.error "Failed addons: #{failed_addons}" unless failed_addons.empty?

      failed_addons
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

    private

    attr_accessor :registration

  end
end
