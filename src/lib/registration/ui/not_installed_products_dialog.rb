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

module Registration
  module UI
    # this class displays and runs the dialog which check all the installed
    # but not registered products warning the user about it and allowing him
    # to take some actions over them.
    class NotInstalledProductsDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

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
        Yast::Popup.Feedback(RegistrationUI::CONTACTING_MESSAGE, _("Checking product conflicts")) do
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
            PushButton(Id(:install), _("Ins&tall addons")),
            PushButton(Id(:sync), _("&Synchronize")),
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
            not_installed = []
            Addon.registered_not_installed.map do |addon|
              begin
                Yast::Popup.Feedback(RegistrationUI::CONTACTING_MESSAGE,
                  _("Installing %s release package") % addon.identifier) do

                  Yast::Pkg.ResolvableInstall(addon.identifier, :product)
                  Yast::Pkg.PkgSolve(true)
                  Yast::Pkg.PkgCommit(0)
                end
              rescue
                not_installed << addon.identifier
              end
            end
            Yast::Popup.Error(_("These addons were not installed:\n\n%s") %
                              not_installed.join("\n")) unless not_installed.empty?
            update_summary
          when :sync
            registration_ui.synchronize_products(SwMgmt.installed_products)
            update_summary
            return :next if !registered_not_installed_addons?
          when :next, :cancel
            return ui
          end
        end
      end

    private

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
        summary << _("<p><b>Synchronize</b> your products if you want to <b>deactivate</b> " \
                     "them at your registration server.</p>")

        summary
      end

      # It updates the summary of registered but not installed products
      # updating also Addon cache.
      def update_summary
        log.info "Updating summary"
        Yast::Popup.Feedback(RegistrationUI::CONTACTING_MESSAGE, _("Updating summary")) do
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
    end
  end
end
