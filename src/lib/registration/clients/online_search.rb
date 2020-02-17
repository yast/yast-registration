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
require "yast2/popup"
require "ui/text_helpers"
require "registration/dialogs/online_search"
require "registration/dialogs/online_search_summary"
require "registration/addon"
require "registration/registration"
require "registration/registration_ui"
require "registration/sw_mgmt"
require "registration/ui/addon_eula_dialog"
require "registration/url_helpers"

Yast.import "Pkg"
Yast.import "Sequencer"
Yast.import "Popup"

module Registration
  module Clients
    # Online search client
    #
    # It offers an interface to search for packages even if they are included in
    # modules which has not been activated yet. It is that the case, the user
    # can select the module for registration before trying to install the package.
    #
    # This client will enable any needed module but package installation should
    # be performed by the regular package manager (`sw_single` client).
    #
    # @see Dialogs::OnlineSearch
    class OnlineSearch
      include Yast::I18n
      extend Yast::I18n
      include Yast::Logger
      include ::UI::TextHelpers

      def initialize
        textdomain "registration"
      end

      # Sequence workflow aliases
      #
      # @see #find_addons
      # @see #search_packages
      # @see #display_summary
      # @see #display_eula
      # @see #register_addons
      # @see #select_packages
      def workflow_aliases
        {
          "check_support"   => ->() { check_support },
          "find_addons"     => ->() { find_addons },
          "search_packages" => ->() { search_packages },
          "display_summary" => ->() { display_summary },
          "display_eula"    => ->() { display_eula },
          "register_addons" => ->() { register_addons },
          "select_packages" => ->() { select_packages }
        }
      end

      # Runs the sequence
      #
      # This method performs these steps:
      #
      #   1. Find the addons
      #   2. Search for packages (UI)
      #   3. Register the addons
      #   4. Display the EULA if needed
      #   5. Select the packages for installation
      #
      # @return [Symbol] Sequence's result (:next or :abort)
      def run
        sequence = {
          "ws_start"        => "check_support",
          "check_support"   => {
            abort: :abort,
            next:  "find_addons"
          },
          "find_addons"     => {
            abort: :abort,
            next:  "search_packages"
          },
          "search_packages" => {
            abort: :abort,
            next:  "display_summary"
          },
          "display_summary" => {
            abort: :abort,
            next:  "display_eula"
          },
          "display_eula"    => {
            abort: :abort,
            next:  "register_addons"
          },
          "register_addons" => {
            next:  "select_packages",
            abort: :abort
          },
          "select_packages" => {
            next:  :next,
            abort: :abort
          }
        }

        log.info "Starting online_search sequence"
        Yast::Sequencer.Run(workflow_aliases, sequence)
      end

    private

      # Determines whether the online search is supported in the running system
      #
      # @return [:next,:abort]
      def check_support
        unless ::Registration::Registration.is_registered?
          registration_required_message
          return :abort
        end
        unless ::Registration::UrlHelpers.default_registration_url?
          smt_not_supported_message
          return :abort
        end

        :next
      end

      # Find all available addons
      #
      # @return [:next]
      def find_addons
        Yast::Popup.Feedback(
          _("Initializing..."), _("Fetching the list of known modules/extensions")
        ) do
          ::Registration::Addon.reset!
          ::Registration::Addon.find_all(registration)
        end
        :next
      end

      # Opens the online search dialog
      #
      # @return [:next]
      def search_packages
        reset_selected_addons_cache!
        package_search_dialog.run
      end

      # Displays a summary of the module/extensions to register and packages to install
      #
      # @return [:next]
      def display_summary
        return :next if selected_packages.empty?
        ::Registration::Dialogs::OnlineSearchSummary.run(
          selected_packages, selected_addons
        )
      end

      # Displays EULAs for the selected addons
      #
      # @return [Symbol] User input (:next, :back, :abort)
      #   or :next if there are not licenses to accept
      #
      def display_eula
        return :next if selected_addons.empty?
        ::Registration::UI::AddonEulaDialog.run(selected_addons)
      end

      # Registers addons
      #
      # @return [Symbol] User input (:next, :back, :abort)
      #   or :next if there are not licenses to accept
      def register_addons
        return :next if selected_addons.empty?
        registration_ui.register_addons(selected_addons, {})
      end

      # Selects packages for installation
      #
      # It displays an error when a package cannot be selected.
      #
      # @return [:next]
      def select_packages
        ::Registration::SwMgmt.select_addon_products
        selected_packages.each do |pkg|
          pkg_install_error_message(pkg.name) unless Yast::Pkg.PkgInstall(pkg.name)
        end
        :next
      end

      def package_search_dialog
        @package_search_dialog ||= ::Registration::Dialogs::OnlineSearch.new
      end

      def registration_ui
        @registration_ui ||= ::Registration::RegistrationUI.new(registration)
      end

      def registration
        return @registration if @registration
        url = ::Registration::UrlHelpers.registration_url
        @registration = ::Registration::Registration.new(url)
      end

      def selected_addons
        return @selected_addons if @selected_addons
        addons = ::Registration::Addon.selected + ::Registration::Addon.auto_selected
        @selected_addons = ::Registration::Addon.registration_order(addons)
      end

      def selected_packages
        package_search_dialog.selected_packages
      end

      def reset_selected_addons_cache!
        @selected_addons = nil
      end

      def pkg_install_error_message(name)
        Yast2::Popup.show(
          format(
            # TRANSLATORS: 'name' is the package's name
            _("Package %{name} could not be selected for installation."),
            name: name
          ),
          headline: :error
        )
      end

      # Returns a message about unregistered systems not being able to use the online search feature
      #
      # @return [String]
      def registration_required_message
        Yast2::Popup.show(
          wrap_text(
            _("YaST requires your system to be registered in order to " \
              "perform an online search. Alternatively, use the web " \
              "version at 'https://scc.suse.com/packages/'.")
          ),
          headline: :error
        )
      end

      # Returns a message about SMT/RMT not supporting the online search feature
      #
      # @return [String]
      def smt_not_supported_message
        Yast2::Popup.show(
          wrap_text(
            _("This system is registered through an SMT/RMT server. " \
              "Unfortunately, the online search feature is not supported " \
              "in this scenario. Alternatively, use the web version at" \
              "'https://scc.suse.com/packages/'.")
          ),
          headline: :error
        )
      end
    end
  end
end
