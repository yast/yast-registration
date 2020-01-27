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
require "cwm/custom_widget"
require "registration/widgets/package_search_form"
require "registration/widgets/remote_packages_table"
require "registration/widgets/remote_package_details"
require "registration/package_search"

Yast.import "Popup"

module Registration
  module Widgets
    # Online package search widget
    #
    # This widget offers a UI to search for packages using the SCC API. It features
    # a search form ({PackageSearchForm}), a list of results ({RemotePackagesTable})
    # and the details of the selected package ({RemotePackageDetails}).
    #
    # Additionally, it allows the user to select packages for installation.
    class PackageSearch < CWM::CustomWidget
      include Yast::Logger

      # @return [Array<String>] List of selected packages
      attr_reader :selected_packages

      # @return [::Registration::PackageSearch,nil] Current search
      attr_reader :search

      # Constructor
      def initialize
        textdomain "registration"
        self.handle_all_events = true
        @selected_packages = [] # list of selected packages
        super
      end

      # @macro seeAbstractWidget
      def contents
        MarginBox(
          0.5,
          0.5,
          HBox(
            VBox(
              search_form,
              VStretch()
            ),
            MinWidth(
              60,
              VBox(
                packages_table,
                package_details
              )
            )
          )
        )
      end

      # @macro seeAbstractWidget
      def handle(event)
        if start_search_event?(event)
          search_package(search_form.text)
        elsif event["WidgetID"] == "remote_packages_table"
          handle_packages_table_event(event)
        end

        log.debug "Event handled #{event.inspect}"
        nil
      end

    private

      # Search form widget
      #
      # @return [PackageSearchForm] Search form widget instance
      def search_form
        @search_form ||= PackageSearchForm.new
      end

      # Packages table widget
      #
      # This widget is used to display the result of the search.
      #
      # @return [RemotePackagesTable] Packages table widget
      def packages_table
        @packages_table ||= RemotePackagesTable.new
      end

      # Package details widget
      #
      # This widget displays the details of the package which is selected in the
      # table.
      #
      # @return [RemotePackageDetails] Package details widget.
      def package_details
        @package_details ||= RemotePackageDetails.new
      end

      # Handles remote packages table events
      #
      # @param event [Hash] Widget event to process
      def handle_packages_table_event(event)
        case event["EventReason"]
        when "Activated"
          toggle_package
        when "SelectionChanged"
          update_details
        end
      end

      # Determines whether the event should start the search
      #
      # @param event [Hash] UI event to check
      # @return [Boolean]
      def start_search_event?(event)
        event["WidgetID"] == "search_form_button" ||
          (event["WidgetID"] == "search_form_text" && event["EventReason"] == "Activated")
      end

      # Performs the search and updates the packages table
      #
      # @param text [String] Text to search for
      def search_package(text)
        @search = ::Registration::PackageSearch.new(text: text)
        # TRANSLATORS: searching for packages
        Yast::Popup.Feedback(_("Searching..."), _("Searching for packages")) do
          selected_package_names = selected_packages.map(&:name)
          @search.packages.each do |pkg|
            pkg.select! if selected_package_names.include?(pkg.name)
          end
        end
        packages_table.change_items(@search.packages)
        update_details
      end

      # Finds out the current package which is selected in the packages table
      #
      # @return [RemotePackage,nil]
      def find_current_package
        return unless search && packages_table.value
        search.packages.find { |p| p.name == packages_table.value }
      end

      # Selects/unselects the current package for installation
      #
      # It does nothing if the package is already installed.
      def toggle_package
        package = find_current_package
        return if package.nil? || package.installed?

        if package.selected?
          unselect_package(package)
        else
          select_package(package)
        end

        packages_table.update_item(package)
        update_details
      end

      # Selects the current package for installation
      #
      # If required, it selects the addon for registration.
      def select_package(package)
        addon = package.addon
        # FIXME: it will crash if addon.nil?
        return unless addon.registered? || addon.selected? || enable_addon?(addon)

        addon.selected unless addon.registered? || addon.selected?
        package.select!
        selected_packages << package
      end

      # Unselects the current package for installation
      def unselect_package(package)
        package.unselect!
        selected_packages.delete(package)
        addon = package.addon
        return unless addon

        addon.unselected unless needed_addon?(package.addon) || !disable_addon?(addon)
      end

      # Updates the package details widget
      def update_details
        current_package = find_current_package
        package_details.update(current_package) if current_package
      end

      # Asks the user to enable the addon
      #
      # @param addon [Addon] Addon to ask about
      def enable_addon?(addon)
        message = format(
          _("'%{name}' module/extension is not enabled for this system.\n" \
            "Do you want to enable it?"),
          name: addon.name
        )
        Yast::Popup.YesNo(message)
      end

      # Asks the user to disable the addon
      #
      # @param addon [Addon] Addon to ask about
      def disable_addon?(addon)
        message = format(
          _("'%{name}' module/extension is not needed anymore.\n" \
            "Do you want to unselect it?"),
          name: addon.name
        )
        Yast::Popup.YesNo(message)
      end

      # Determines whether the addon is still needed
      def needed_addon?(addon)
        selected_packages.any? { |pkg| pkg.addon == addon }
      end
    end
  end
end
