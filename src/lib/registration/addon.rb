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

require 'tsort'

module Registration
  class Addon
    class << self
      def find_all_available(registration)
        pure_addons = registration.get_addon_list
        pure_addons.reduce([]) do |res, addon|
          res.concat(create_addon_with_deps(addon))
        end
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

    attr_reader :children
    attr_accessor :depends_on
    def initialize pure_addon
      @pure_addon = pure_addon
      @children = []
    end
  end

  # class for sorting Addons according to their dependencies
  # SCC requires to register addons in their dependency order
  # @see TSort example http://ruby-doc.org/stdlib-2.1.0/libdoc/tsort/rdoc/TSort.html#module-TSort-label-A+Simple+Example
  class AddonSorter < Hash
    include TSort

    alias tsort_each_node each_key

    def tsort_each_child(node, &block)
      fetch(node).each(&block)
    end

    # computes registration order of add-ons acording to their dependencies
    # raises KeyError on missing dependency
    # @param addons [Array<Addons>] input list with addons
    # @return [Array<Addons>] input list sorted according to Addon dependencies
    def self.registration_order(addons)
      solver = AddonSorter.new

      # fill the solver with addon dependencies
      addons.each do |a|
        solver[a] = a.depends_on
      end

      # compute the order using tsort
      solver.tsort
    end
  end

end
