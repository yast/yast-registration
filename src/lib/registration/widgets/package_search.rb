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
require "registration/widgets/toggle_package_status"
require "yast2/popup"

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

      # @return [Array<RemotePackage>] Packages found in the current search
      attr_reader :packages

      # Constructor
      #
      # @param controller [Registration::Controllers::PackageSearch] Package search controller
      def initialize(controller)
        textdomain "registration"
        self.handle_all_events = true
        @controller = controller
        @packages = []
        super()
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
                MinHeight(14, packages_table),
                HBox(Right(toggle_package_status)),
                package_details
              )
            )
          )
        )
      end

      # @macro seeAbstractWidget
      def handle(event)
        if start_search_event?(event)
          search_package(search_form.text, search_form.ignore_case)
        elsif event["WidgetID"] == "remote_packages_table"
          handle_packages_table_event(event)
        elsif event["WidgetID"] == "toggle_package_status"
          toggle_package
        end

        log.debug "Event handled #{event.inspect}"
        nil
      end

    private

      # @return [Registration::Controllers::PackageSearch] Widget's controller
      attr_reader :controller

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

      # Package status toggle widget
      #
      # @return [TogglePackageStatus] a button to toggle, if possible, the status of current package
      def toggle_package_status
        @toggle_package_status ||= TogglePackageStatus.new
      end

      # Handles remote packages table events
      #
      # @param event [Hash] Widget event to process
      def handle_packages_table_event(event)
        case event["EventReason"]
        when "Activated"
          toggle_package
        when "SelectionChanged"
          update
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
      # @param text        [String] Text to search for
      # @param ignore_case [Boolean] Whether the search is case sensitive or not
      def search_package(text, ignore_case)
        return unless valid_search_text?(text)
        # TRANSLATORS: searching for packages
        Yast::Popup.Feedback(_("Searching..."), _("Searching for packages")) do
          @packages = controller.search(text, ignore_case)
          selected_package_ids = controller.selected_packages.map(&:id)
          @packages.each do |pkg|
            pkg.select! if selected_package_ids.include?(pkg.id)
          end
        end
        packages_table.change_items(packages)
        update
      end

      # Finds out the current package which is selected in the packages table
      #
      # @return [RemotePackage,nil]
      def find_current_package
        packages.find { |p| p.id == packages_table.value }
      end

      # Selects/unselects the current package for installation
      def toggle_package
        package = find_current_package

        return unless package

        controller.toggle_package(package)
        packages_table.update_item(package)
        update
      end

      # Updates the UI according to selected package
      #
      # Updating the package details and actions
      def update
        current_package = find_current_package

        toggle_package_status.package = current_package
        toggle_package_status.refresh

        if current_package
          package_details.update(current_package)
        else
          package_details.clear
        end
      end

      MINIMAL_SEARCH_TEXT_SIZE = 2

      # Determines whether the search text is valid or not
      #
      # @param text [String] Text to search for
      def valid_search_text?(text)
        return true if text.to_s.size >= MINIMAL_SEARCH_TEXT_SIZE
        Yast2::Popup.show(
          format(
            # TRANSLATORS: the minimal size of the text to search for package names
            _("Please, type at least %{minimal_size} characters to search for."),
            minimal_size: MINIMAL_SEARCH_TEXT_SIZE
          )
        )
        false
      end
    end
  end
end
