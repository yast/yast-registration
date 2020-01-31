# Copyright (c) [2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "registration/package_search"

Yast.import "Popup"
Yast.import "HTML"

module Registration
  module Controllers
    # Implements the actions and keeps the state for the package search feature
    class PackageSearch
      include Yast::I18n

      # @return [Array<RemotePackage>] List of selected packages
      attr_reader :selected_packages

      # Constructor
      def initialize
        textdomain "registration"
        @selected_packages = []
      end

      # Performs a package search
      #
      # @param text [String] Term to search for
      # @return [Array<Registration::RemotePackage>] List of packages
      def search(text)
        @search = ::Registration::PackageSearch.new(text: text)
        @search.packages
      end

      # Selects/unselects the current package for installation
      #
      # It does nothing if the package is already installed.
      def toggle_package(package)
        return if package.installed?

        if package.selected?
          unselect_package(package)
        else
          select_package(package)
        end
      end

    private

      # Selects the current package for installation
      #
      # If required, it selects the corresponding addon
      #
      # @param package [RemotePackage] Package to select
      def select_package(package)
        log.info "Selecting package: #{package.inspect}"
        addon = package.addon
        select_addon(addon) if addon
        set_package_as_selected(package) if addon.nil? || addon.selected? || addon.registered?
      end

      # Unselects the current package for installation
      #
      # If not needed, unselects the corresponding addon
      #
      # @param package [RemotePackage] Package to unselect
      #
      # @see #unselect_addon
      # @see #unselect_package!
      def unselect_package(package)
        log.info "Unselecting package: #{package.inspect}"
        unset_package_as_selected(package)
        unselect_addon(package.addon) if package.addon
      end

      # Selects the given addon if needed
      #
      # If the addon is registered or selected, does nothing. If the addon
      # was auto selected, it will be marked as selected.
      #
      # @param addon [Addon] Addon to select
      def select_addon(addon)
        log_addon("selecting the addon", addon)
        return if addon.registered? || addon.selected?
        addon.selected if addon.auto_selected? || enable_addon?(addon)
      end

      # Unselects the given addon if required
      #
      # @param addon [Addon] Addon to unselect
      def unselect_addon(addon)
        log_addon("unselecting the addon", addon)
        return if addon.registered? || needed_addon?(addon)
        addon.unselected if disable_addon?(addon)
      end

      # Sets the package as selected
      #
      # Marks the package as selected and adds it to the list of selected packages.
      #
      # @param package [RemotePackage] Package to add
      def set_package_as_selected(package)
        package.select!
        selected_packages << package
      end

      # Unsets the package as selected
      #
      # Marks the package as not selected and removes it from the list of selected packages.
      #
      # @param package [RemotePackage] Package to remove
      def unset_package_as_selected(package)
        package.unselect!
        selected_packages.delete(package)
      end

      # Asks the user to enable the addon
      #
      # @param addon [Addon] Addon to ask about
      def enable_addon?(addon)
        description = Yast::HTML.Para(
          format(
            _("The selected package is provided by the '%{name}', " \
              "which is not enabled on this system yet."),
            name: addon.name
          )
        )

        unselected_deps = addon.dependencies.reject { |d| d.selected? || d.registered? }
        if !unselected_deps.empty?
          description << Yast::HTML.Para(
            format(
              _("Additionally, '%{name}' depends on the following modules/extensions:"),
              name: addon.name
            )
          )
          description << Yast::HTML.List(unselected_deps.map(&:name))
        end
        # TRANSLATORS: 'it' and 'them' refers to the modules/extensions to enable
        question = n_(
          "Do you want to enable it?", "Do you want to enable them?", unselected_deps.size + 1
        )
        yes_no_popup(description + question)
      end

      # Asks the user to disable the addon
      #
      # @param addon [Addon] Addon to ask about
      def disable_addon?(addon)
        message = format(
          _("The '%{name}' is not needed anymore.\n" \
            "Do you want to unselect it?"),
          name: addon.name
        )
        yes_no_popup(message)
      end

      # Determines whether the addon is still needed
      def needed_addon?(addon)
        selected_packages.any? { |pkg| pkg.addon == addon }
      end

      # Asks a yes/no question
      #
      # @return [Boolean] true if the answer is affirmative; false otherwise
      def yes_no_popup(message)
        ret = Yast2::Popup.show(message, richtext: true, buttons: :yes_no)
        log.info "yes/no pop-up. The answer is '#{ret}"
        ret == :yes
      end

      # Logs information about a given addon
      #
      # @param msg [String] Message to display at the beginning of the line
      # @param addon [Registration::Addon]
      def log_addon(msg, addon)
        log.info "#{msg}: #{addon.inspect}, registered=#{addon.registered?}, selected=#{addon.selected?}" \
          "auto_selected=#{addon.auto_selected?}"
      end
    end
  end
end
