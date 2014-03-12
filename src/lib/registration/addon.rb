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
    # product data needed for registration
    attr_reader :name, :version, :arch
    # additional data: UI labels, dependencies on other add-ons and
    # a flag indicating required registration key
    attr_reader :label, :description, :depends_on, :regkey_needed

    def initialize(name, version, arch, label: "", description: "",
        depends_on: [], regkey_needed: true)
      @name = name
      @version = version
      @arch = arch
      @label = label
      @description = description
      @depends_on = depends_on
      @regkey_needed = regkey_needed
    end

    # recursively collect all addon dependecies and create a flat list
    # @return [Array<Addon>]
    def required_addons
      # this addon dependencies plus their dependencies
      depends_on.inject(depends_on.dup) do |acc, dep|
        acc.concat(dep.required_addons)
        # remove duplicates
        acc.uniq
      end
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
