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

module Registration
  class Addon
    class << self
      def find_all(registration)
        return @cached_addons if @cached_addons
        pure_addons = registration.get_addon_list
        @cached_addons = pure_addons.reduce([]) do |res, addon|
          res.concat(create_addon_with_deps(addon))
        end
      end

      def registered
        @registered ||= []
      end

      def selected
        @selected ||= []
      end

      private

      def create_addon_with_deps(root)
        root_addon = Addon.new(root)
        result = [ root_addon ]

        (root.extensions || []).each do |ext|
          child = create_addon_with_deps(ext)
          result.concat(child)
          child.first.depends_on = root_addon
          root_addon.children << child.first
        end

        return result
      end
    end

    extend Forwardable

    attr_reader :children
    attr_accessor :depends_on, :regcode

    # delegate methods to underlaying suse connect object
    def_delegators :@pure_addon,
      :free,
      :product_ident,
      :short_name,
      :long_name,
      :description,
      :eula_url,
      :arch,
      :version

    def initialize pure_addon
      @pure_addon = pure_addon
      @children = []
    end

    def selected?
      Addon.selected.include?(self)
    end

    def selected
      Addon.selected << self unless selected?
    end

    def unselected
      Addon.selected.delete(self) if selected?
    end

    def registered?
      Addon.registered.include?(self)
    end
  end
end
