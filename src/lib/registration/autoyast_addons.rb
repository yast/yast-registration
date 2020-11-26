# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
# ------------------------------------------------------------------------------
#

require "yast"
require "y2packager/product_control_product"

module Registration
  # This class handles the AutoYaST addons
  class AutoyastAddons
    include Yast::I18n

    attr_accessor :requested_addons, :selected_addons

    Yast.import "Report"
    Yast.import "Pkg"
    Yast.import "Arch"

    # Constructor
    # @param requested_addons [Array<Hash<String,String>>] the addons configuration
    #   from the AutoYaST profile
    # @param registration [Registration::Registration] the Registration object to use
    #   for registering the addons
    def initialize(requested_addons, registration)
      textdomain "registration"

      self.requested_addons = requested_addons
      self.registration = registration
    end

    # read the available addons from the server, sort the addons from the profile
    # according to the dependencies
    def select
      # ask the server for all available addons (with UI feedback)
      all_addons = registration_ui.get_available_addons

      # remove the addons marked as not available
      rejected = all_addons.reject! { |a| a.available? == false }
      log.info("Not available addons: #{rejected.map(&:label).inspect}") if rejected

      # select the requested addons from the available addons
      self.selected_addons = select_addons(all_addons)
    end

    # register the selected addons, the #select method must be called before
    def register
      regcodes = collect_reg_codes
      registration_ui.register_addons(selected_addons, regcodes)
    end

  private

    attr_writer :selected_addons
    attr_accessor :registration

    # select the requested addons
    # @param all_addons [Array<Registration::Addon>] all addons available on the server
    def select_addons(all_addons)
      # select the requested addons from the AY profile
      requested_addons.each do |addon|
        # Set architecture if it is not defined in the requested addon
        requested_arch = addon["arch"] ||
          Y2Packager::ProductControlProduct::REG_ARCH[Yast::Arch.architecture] ||
          Yast::Arch.architecture

        log.info("Select addon: #{addon.inspect}")
        server_addons = all_addons.select do |a|
          a.identifier == addon["name"] &&
            (!addon["version"] || a.version == addon["version"]) && # version defined ?
            a.arch == requested_arch
        end
        # Select the highest version
        server_addon = server_addons.max do |b, c|
          Yast::Pkg.CompareVersions(b.version, c.version)
        end

        if server_addon
          # mark it as selected
          server_addon.selected
        else
          # otherwise report an error
          report_missing_addon(addon)
        end
      end

      ordered_addons
    end

    # report error about a missing addon
    # @param addon [Hash]
    def report_missing_addon(addon)
      log.error("Unavailable addon: #{addon.inspect}")
      Yast::Report.Error(
        # TRANSLATORS: %s is an add-on name (including version and arch)
        # from the AutoYast XML installation profile
        _("Add-on '%s'\nis not available for registration.") % \
          "#{addon["name"]}-#{addon["version"]}-#{addon["arch"]}"
      )
    end

    # Order the addons according to thier dependencies, the result is sorted
    # in the registration order. The result also includes the dependant addons
    # (even not specified in the profile).
    # @return [Array<Registration::Addon>]
    def ordered_addons
      # include also the automatically selected dependent modules/extensions
      ret = Addon.registration_order(Addon.selected + Addon.auto_selected)

      log.info("Add-ons to register: #{ret.map(&:label).inspect}")

      ret
    end

    # collect the registration codes specified in the profile
    # @return [Hash<String,String>] mapping "product identifier" => "reg code"
    def collect_reg_codes
      ret = {}

      requested_addons.each do |a|
        ret[a["name"]] = a["reg_code"] if a["reg_code"]
      end

      log.info("Found reg codes for addons: #{ret.keys.inspect}")

      ret
    end

    def registration_ui
      @registration_ui ||= RegistrationUI.new(registration)
    end
  end
end
