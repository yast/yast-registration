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
require "set"
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

        @cached_addons = load_addons(registration)

        dump_addons

        @cached_addons
      end

      def reset!
        @cached_addons = nil
        @registered    = nil
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

      # invalidates automatically selected addons. Resulting in recalculating it.
      def reset_auto_selected
        @auto_selected = nil
      end

      # list of auto selected add-ons
      def auto_selected
        @auto_selected ||= detect_auto_selection
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
      # @return [Array<Addon>] list of addons, where the first one is
      #   the one based on root and rest is its children
      def create_addon_with_deps(root)
        # to_process is array of pairs, where first is pure addon to process and second is
        # its dependency. Currently SUSE::Connect structure have only one dependency.
        to_process = [[root, nil]]
        processed = Set.new
        result = []

        to_process.each do |(pure, dependency)|
          # this avoid endless loop if there is circular dependency.
          next if processed.include?(pure)
          processed << pure
          addon = Addon.new(pure)
          result << addon
          addon.depends_on = dependency
          (pure.extensions || []).each do |ext|
            to_process << [ext, addon]
          end
        end

        result
      end

      def load_addons(registration)
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

      def detect_auto_selection
        required = selected + registered

        # here we use sets as for bigger dependencies this can be quite slow
        # how it works? it fills set with selected and registered items and it will
        # adds recursive all its children and then subtract that manually selected
        # or registered.
        already_processed = Set.new(required)
        to_process = required.dup

        to_process.each do |addon|
          already_processed << addon
          # prepared when depends_on support multiple addons
          dependencies = addon.depends_on ? [addon.depends_on] : []
          new_addons = dependencies.reject { |c| already_processed.include?(c) }
          to_process.concat(new_addons)
        end

        to_process - required
      end
    end

    extend Forwardable

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
      :release_stage,
      :version,
      :repositories

    # the constructor
    # @param pure_addon [SUSE::Connect::Product] a pure add-on from the registration server
    def initialize(pure_addon)
      @pure_addon = pure_addon
    end

    # is the add-on selected
    # @return [Boolean] true if the add-on is selected
    def selected?
      Addon.selected.include?(self)
    end

    # is the add-on auto_selected
    # @return [Boolean] true if the add-on is auto_selected
    def auto_selected?
      Addon.auto_selected.include?(self)
    end

    # select the add-on
    def selected
      return if selected?

      Addon.selected << self
      Addon.reset_auto_selected
    end

    # unselect the add-on
    def unselected
      return unless selected?

      Addon.selected.delete(self)
      Addon.reset_auto_selected
    end

    # returns status of addon. Potential statuses are :registered, :selected, :auto_selected,
    # :available and :none.
    # @return [Symbol]
    def status
      return :registered if registered?
      return :selected if selected?
      return :auto_selected if auto_selected?
      return :available if available?

      :none
    end

    # toggle the selection state of the add-on
    def toggle_selected
      if selected?
        unselected
      else
        selected
      end
      Addon.reset_auto_selected
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

    def beta_release?
      release_stage == "beta"
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

    def self.dump_addons
      # dump the downloaded data to a file for easier debugging,
      # avoid write failures when running as an unprivileged user (rspec tests)
      return unless File.writable?("/var/log/YaST2")

      require "yaml"
      header = "# see " \
        "https://github.com/yast/yast-registration/tree/master/devel/dump_reader.rb\n" \
        "# for an example how to read this dump file\n"
      File.write("/var/log/YaST2/registration_addons.yml",
        header + @cached_addons.to_yaml)
    end
  end
end
