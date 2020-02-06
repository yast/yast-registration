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
require "cwm/dialog"
require "registration/controllers/package_search"
require "registration/widgets/package_search"

module Registration
  module Dialogs
    # Dialog to search for packages
    #
    # This dialog embeds a {Registration::Widgets::PackageSearch} returning
    # the list of selected packages.
    class OnlineSearch < CWM::Dialog
      # @return [Array<RemotePackage>] Selected packages after running the dialog
      attr_reader :selected_packages

      # Constructor
      def initialize
        textdomain "registration"
        @selected_packages = []
        super
      end

      # @macro seeAbstractWidget
      def title
        # TRANSLATORS: title for the dialog to search for package through all modules/extensions
        _("Online Search")
      end

      # @macro seeAbstractWidget
      def contents
        VBox(package_search_widget)
      end

      # Returns the list of selected packages
      #
      # @return [Symbol] Dialog's result (:next or :abort)
      #   packages. If the user aborted the dialog, it returns an empty array.
      #
      # @macro seeAbstractWidget
      def run
        ret = super
        @selected_packages = ret == :next ? controller.selected_packages : []
        ret
      end

      # @macro seeDialog
      def abort_button
        Yast::Label.CancelButton
      end

      # @macro seeDialog
      def back_button
        ""
      end

      # @macro seeDialog
      def help
        _("The online search feature allows the user to search for packages across all " \
          "modules and extensions, including those that have not been activated for this " \
          "system.\n\nOnce the wanted package is found, the user can select it for " \
          "installation. If it belongs to a not activated module, YaST will allow activating " \
          "the module/extension. Bear in mind that the activation will take place at the end, " \
          "after the user clicks the Next button.")
      end

    private

      # Package search widget
      #
      # @return [Registration::Widgets::PackageSearch]
      def package_search_widget
        @package_search_widget ||= ::Registration::Widgets::PackageSearch.new(controller)
      end

      # Package search controller
      #
      # @return [Registration::Controllers::PackageSearch]
      def controller
        @controller ||= ::Registration::Controllers::PackageSearch.new
      end
    end
  end
end
