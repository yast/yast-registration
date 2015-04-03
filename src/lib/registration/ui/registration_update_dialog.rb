
require "yast"
require "yast/suse_connect"

require "registration/registration"
require "registration/registration_ui"
require "registration/storage"
require "registration/sw_mgmt"
require "registration/helpers"
require "registration/url_helpers"
require "registration/ui/local_server_dialog"

module Registration
  module UI
    class RegistrationUpdateDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Mode"
      Yast.import "GetInstArgs"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Report"

      # run new dialog for updating the current registration
      def self.run
        dialog = RegistrationUpdateDialog.new
        dialog.run
      end

      def initialize
        textdomain "registration"
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        log.info "Diplaying registration update dialog"

        Yast::Wizard.SetContents(
          _("Registration"),
          Label(_("Registration is being updated...")),
          _("The previous registration is being updated."),
          GetInstArgs.enable_back,
          GetInstArgs.enable_next || Mode.normal
        )

        handle_dialog
      end

      attr_accessor :registration, :registration_ui

      private

      def handle_dialog
        if update_system_registration && refresh_base_product && refresh_addons
          log.info "Registration update succeeded"
          :next
        else
          # force reinitialization to allow to use a different URL
          self.registration = nil
          # automatic registration refresh during system upgrade failed, register from scratch
          Report.Error(_("Automatic registration upgrade failed.\n" \
                "You can manually register the system from scratch."))
          :register
        end
      end

      # update system registration, update the target distribution
      # @return [Boolean] true on success
      def update_system_registration
        return false if init_registration == :cancel
        registration_ui.update_system
      end

      # update base product registration
      # @return [Boolean] true on success
      def refresh_base_product
        return false if init_registration == :cancel

        success, product_service = registration_ui.update_base_product

        if success && product_service && !registration_ui.install_updates?
          success = registration_ui.disable_update_repos(product_service)
        end

        success
      end

      def refresh_addons
        addons = registration_ui.get_available_addons

        failed_addons = registration_ui.update_addons(addons,
          enable_updates: registration_ui.install_updates?)

        # if update fails preselest the addon for full registration
        failed_addons.each(&:selected)

        true
      end

      # initialize the Registration object
      # @return [Symbol, nil] returns :cancel if the URL selection was canceled
      def init_registration
        return if registration

        url = UrlHelpers.registration_url
        return :cancel if url == :cancel
        log.info "Initializing registration with URL: #{url.inspect}"
        self.registration = Registration.new(url)
        self.registration_ui = RegistrationUI.new(registration)
      end
    end
  end
end
