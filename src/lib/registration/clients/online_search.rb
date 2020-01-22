# Copyright (c) [2019] SUSE LLC
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
require "registration/dialogs/online_search"
require "registration/addon"
require "registration/registration"
require "registration/registration_ui"
require "registration/ui/addon_eula_dialog"
require "registration/url_helpers"

Yast.import "Installation"
Yast.import "Pkg"
Yast.import "Sequencer"

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

      def initialize
        textdomain "registration"
      end

      # Sequence workflow aliases
      #
      # @see #find_addons
      # @see #package_search
      # @see #commit
      def workflow_aliases
        {
          "find_addons"     => ->() { find_addons },
          "search"          => ->() { search_packages },
          "display_eula"    => ->() { display_eula },
          "register_system" => ->() { register_system },
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
      #   4. Select the packages for installation
      #
      # @return [Symbol] Sequence's result (:next or :abort)
      def run
        sequence = {
          "ws_start"        => "find_addons",
          "find_addons"     => {
            abort: :abort,
            next:  "search"
          },
          "search"          => {
            abort: :abort,
            next:  "display_eula"
          },
          "display_eula"    => {
            abort: :abort,
            next:  "register_system"
          },
          "register_system" => {
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

      def find_addons
        ::Registration::Addon.find_all(registration)
        :next
      end

      # Opens the online search dialog
      def search_packages
        reset_selected_addons_cache!
        package_search_dialog.run
      end

      # Registers the system and the base product
      def register_system
        return :next if ::Registration::Registration.is_registered? || selected_addons.empty?
        success = registration_ui.register_system_and_base_product.first
        success ? :next : :abort
      end

      # display EULAs for the selected addons
      def display_eula
        return :next if selected_addons.empty?
        ::Registration::UI::AddonEulaDialog.run(selected_addons)
      end

      def register_addons
        return :next if selected_addons.empty?
        registration_ui.register_addons(selected_addons, {})
      end

      def select_packages
        package_search_dialog.selected_packages.each do |pkg|
          Yast::Pkg.PkgInstall(pkg.name)
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

      def reset_selected_addons_cache!
        @selected_addons = nil
      end
    end
  end
end
