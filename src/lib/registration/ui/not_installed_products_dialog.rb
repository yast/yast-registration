# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE.
#
# To contact SUSE about this file by physical or electronic mail, you may find
# current contact information at www.suse.com.
# ------------------------------------------------------------------------------

require "yast"
require "registration/sw_mgmt"
require "registration/helpers"
require "uri"

module Registration
  module UI
    # this class displays and runs the dialog which check all the installed
    # but not registered products warning the user about it and allowing him
    # to take some actions over them.
    class NotInstalledProductsDialog
      include Yast::Logger
      include Yast::I18n
      extend Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "UI"
      Yast.import "Popup"
      Yast.import "Pkg"
      Yast.import "Packages"
      Yast.import "PackagesUI"

      REGISTRATION_CHECK_MSG = N_("Checking registration status")

      attr_accessor :registration, :registration_ui

      def self.run
        dialog = NotInstalledProductsDialog.new
        dialog.run
      end

      def initialize
        textdomain "registration"

        self.registration = Registration.new(UrlHelpers.registration_url)
        self.registration_ui = RegistrationUI.new(registration)
      end

      def run
        Yast::Popup.Feedback(RegistrationUI::CONTACTING_MESSAGE, _(REGISTRATION_CHECK_MSG)) do
          return :next if !registered_not_installed_addons?
        end

        Yast::UI.OpenDialog(Opt(:decorated), content)

        begin
          handle_dialog
        ensure
          Yast::UI.CloseDialog
        end
      end

      private

      def content
        VBox(
          MinWidth(80,
            MinHeight(15,
              VWeight(25, RichText(Id(:summary), not_installed_addons_summary))
            )
          ),
          ButtonBox(
            PushButton(Id(:cancel), Opt(:key_F9, :cancelButton), Yast::Label.AbortButton),
            # FIXME: Maybe we could remove this option and just warn the user
            PushButton(Id(:install), _("Ins&tall products")),
            PushButton(Id(:sync), _("&Deactivate")),
            PushButton(Id(:next), Opt(:okButton, :key_F10, :default), _("Continue"))
          )
        )
      end

      def handle_dialog
        loop do
          Yast::UI.SetFocus(:next)
          ui = Yast::UI.UserInput
          log.info "User input: #{ui}"
          case ui
          when :install
            not_installed = install_products
            # TRANSLATORS: Popup error showing all the addons that weren't
            # installed, %s is the addons identifiers.
            Yast::Popup.Error(_("These addons were not installed:\n\n%s") %
                              not_installed.join("\n")) unless not_installed.empty?
            update_summary
          when :sync
            registration_ui.synchronize_products(SwMgmt.installed_products)
            update_summary
          when :next, :cancel
            return ui
          end

          return :next if !registered_not_installed_addons?
        end
      end

      # Install the not installed products
      # @return [Array] list of not installed (failed) products, empty list on success
      def install_products
        not_installed = []

        Addon.registered_not_installed.each do |addon|
          # FIXME: fix the product installation, the add-on name might not match
          # the libzypp product name
          # Check for possible conflicts and let the user solve them,
          # confirm package licenses if there are any,
          # and run the package installation
          if addon_product_installable?(addon)

            result = Yast::Pkg.PkgCommit(0)
            # success?
            if result && result[1].empty?
              # FIXME: This method is not available in SLE-12-GA
              # Yast::PackagesUI.show_update_messages(result)
              next
            end
          end

          log.error("Product #{addon.identifier} could not be installed")
          # revert the changes
          Yast::Pkg.PkgApplReset
          Yast::Pkg.PkgReset
          not_installed << addon.identifier
        end

        not_installed
      end

      # RichText summary of the installed but not registered products.
      #
      # @return [String]
      def not_installed_addons_summary
        # TRANSLATORS: A RichText warning about all the products registered but
        #   not installed. (1/2)
        summary = _("<p>The addons listed below are registered but not installed: </p>")

        summary << "<ul>#{not_installed_addon_names.map { |a| "<li>#{a}</li>" }.join("")}</ul>"

        # TRANSLATORS: A RichText warning about all the products registered but
        #   not installed. (2/2)
        summary << _("<p>It's preferable to <b>deactivate</b> your products at your " \
                     "registration server if you don't plan to use them anymore.</p>")

        summary
      end

      # It updates the summary of registered but not installed products
      # updating also Addon cache.
      def update_summary
        log.info "Updating summary"
        Yast::Popup.Feedback(RegistrationUI::CONTACTING_MESSAGE, _(REGISTRATION_CHECK_MSG)) do
          Addon.reset!
          Addon.find_all(registration)
        end

        Yast::UI.ChangeWidget(Id(:summary), :Value, not_installed_addons_summary)
      end

      # @return [Boolean] true if in the registration server exists some
      # registered but not installed addon; false otherwise
      def registered_not_installed_addons?
        !Addon.registered_not_installed.empty?
      end

      # @return [Array<String>] return an array with all the registered but not
      #   installed addon names.
      def not_installed_addon_names
        Addon.registered_not_installed.map(&:name)
      end

      # @param addon [Registration::Addon] addon to be installed
      # @return [Boolean] true if the given addon is installable
      def addon_product_installable?(addon)
        product = product_from_addon_repos(addon)
        return false if !product || !Yast::Pkg.ResolvableInstall(product["name"], :product)

        if !Yast::Pkg.PkgSolve(true)
          return false if Yast::PackagesUI.RunPackageSelector("mode" => :summaryMode) != :accept
        end

        Yast::PackagesUI.ConfirmLicenses
      end

      # Find the product resolvables matching the repository url with the addon
      # ones.
      #
      # @param addon [Registration::Addon]
      # @return [Hash] product which repository url match with addon ones
      def product_from_addon_repos(addon)
        Yast::Pkg.ResolvableProperties("", :product, "").find do |product|
          return false if product["status"] != :available

          product_url = SwMgmt.repository_data(product["source"]).fetch("url", "")

          addon.repositories.any? { |r| no_query_uri(product_url) == no_query_uri(r["url"]) }
        end
      end

      # Given an 'url' return an URI object without query parameters and
      # without slashes at the end of the path
      #
      # FIXME: This method could be moved to UrlHelpers or to URL module.
      #
      # @param [String] url to parse
      # @return [URI] parsed url without query and without slashes at the end
      # of the path
      def no_query_uri(url)
        uri = URI.parse(url)
        uri.query = nil
        uri.path.gsub!(/\/+\z/, "")
        uri
      end
    end
  end
end
