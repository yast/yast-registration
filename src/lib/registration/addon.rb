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

require "forwardable"
require "registration/sw_mgmt"

module Registration
  # this is a wrapper class around SUSE::Connect::Product object
  class Addon
    class << self
      # read the remote add-on from the registration server
      # @param registration [Registration::Registration] use this object for
      #  reading the remote add-ons
      def find_all(registration)
        return @cached_addons if @cached_addons
        pure_addons = registration.get_addon_list
        # get IDs of the already activated addons
        activated_addon_ids = registration.activated_products.map(&:id)

        @cached_addons = pure_addons.reduce([]) do |res, addon|
          yast_addons = create_addon_with_deps(addon)

          # mark as registered if found in the status call
          yast_addons.each do |yast_addon|
            yast_addon.registered if activated_addon_ids.include?(yast_addon.id)
          end

          res.concat(yast_addons)
        end
      end

      # list of registered add-ons
      # @return [Array<Addon>] registered add-ons
      def registered
        @registered ||= []
      end

      # list of selected add-ons
      # @return [Array<Addon>] selected add-ons
      def selected
        @selected ||= []
      end

      # return add-ons which are registered but not installed in the system
      # @return [Array<Addon>] the list of add-ons
      def registered_not_installed
        registered.select do |addon|
          !SwMgmt.installed_products.find do |product|
            product["name"] == addon.identifier &&
              product["version_version"] == addon.version &&
              product["arch"] == addon.arch
          end
        end
      end

      private

      # create an Addon from a SUSE::Connect::Product
      # @param root [SUSE::Connect::Product] the root add-on object
      # @return [Addon] created Addon object
      def create_addon_with_deps(root)
        root_addon = Addon.new(root)
        result = [root_addon]

        (root.extensions || []).each do |ext|
          child = create_addon_with_deps(ext)
          result.concat(child)
          child.first.depends_on = root_addon
          root_addon.children << child.first
        end

        result
      end
    end

    extend Forwardable

    attr_reader :children
    attr_accessor :depends_on, :regcode

    # delegate methods to underlaying suse connect object
    def_delegators :@pure_addon,
      :arch,
      :description,
      :eula_url,
      :free,
      :friendly_name,
      :id,
      :identifier,
      :name,
      :product_type,
      :release_type,
      :version

    # the constructor
    # @param pure_addon [SUSE::Connect::Product] a pure add-on from the registration server
    def initialize(pure_addon)
      @pure_addon = pure_addon
      @children = []
    end

    # is the add-on selected
    # @return [Boolean] true if the add-on is selectec
    def selected?
      Addon.selected.include?(self)
    end

    # select the add-on
    def selected
      Addon.selected << self unless selected?
    end

    # unselect the add-on
    def unselected
      Addon.selected.delete(self) if selected?
    end

    # has been the add-on registered?
    # @return [Boolean] true if the add-on has been registered
    def registered?
      Addon.registered.include?(self)
    end

    # mark the add-on as registered
    def registered
      Addon.registered << self unless registered?
    end

    # just internally mark the addon as NOT registered, not a real unregistration
    def unregistered
      Addon.registered.delete(self) if registered?
    end

    # get a product printable name (long name if present, fallbacks to the short name)
    # @return [String] label usable in UI
    def label
      (friendly_name && !friendly_name.empty?) ? friendly_name : name
    end

    # can be the addon selected in UI or should it be disabled?
    # return [Boolean] true if it should be enabled
    def selectable?
      # Do not support unregister
      return false if registered?
      # Do not select not available addons
      return false if !available?
      # Do not allow to select child without selected or already registered parent
      return false if depends_on && !(depends_on.selected? || depends_on.registered?)
      # Do not allow to unselect parent if any children is selected
      return false if children.any?(&:selected?)

      true
    end

    # Convert to a Hash, exports only the basic Addon properties
    # @param [Boolean] release_type_string if true the "release_type" atribute
    #   will be always a String (nil will be converted to "nil")
    # @return [Hash] Hash with basic Addon properties
    def to_h(release_type_string: false)
      {
        "name"         => identifier,
        "arch"         => arch,
        "version"      => version,
        "release_type" => (release_type.nil? && release_type_string) ? "nil" : release_type
      }
    end

    # is the addon available? SMT may have mirrored only some extensions,
    # the not mirrored extensions are marked as not available
    # @return [Boolean] true if the addon is available to register
    def available?
      # explicitly check for false, undefined (nil) means it is available,
      # it's only reported by SMT
      @pure_addon.available != false
    end

    # Checks whether this addon updates an old addon
    # @param [Hash] old_addon addon Hash received from pkg-bindings
    # @return [Boolean] true if it updates the old addon, false otherwise
    def updates_addon?(old_addon)
      old_addon["name"] == identifier || old_addon["name"] == @pure_addon.former_identifier
    end

    def matches_remote_product?(remote_product)
      [:arch, :identifier, :version, :release_type].all? do |attr|
        send(attr) == remote_product.send(attr)
      end
    end
  end
end
