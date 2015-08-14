
require "yast"
require "yast/suse_connect"

require "registration/registration"
require "registration/registration_ui"
require "registration/storage"
require "registration/sw_mgmt"
require "registration/helpers"
require "registration/url_helpers"
require "registration/ui/local_server_dialog"
require "registration/ui/abort_confirmation"

module Registration
  module UI
    # this class displays and runs the dialog for registering the base system
    class BaseSystemRegistrationDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Mode"
      Yast.import "GetInstArgs"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Popup"

      # create and run the dialog for registering the base system
      # @return [Symbol] the user input
      def self.run
        dialog = BaseSystemRegistrationDialog.new
        dialog.run
      end

      # the constructor
      def initialize
        textdomain "registration"
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        log.info "Diplaying registration dialog"

        Yast::Wizard.SetContents(
          # dialog title
          _("Registration"),
          content,
          help_text,
          Yast::GetInstArgs.enable_back || (Yast::Mode.normal && Registration.is_registered?),
          Yast::GetInstArgs.enable_next || Yast::Mode.normal
        )

        # disable the input fields when already registered
        disable_widgets if Registration.is_registered? && !Yast::Mode.normal

        handle_dialog
      end

      attr_accessor :registration

      private

      # width of reg code input field widget
      REG_CODE_WIDTH = 33

      def disable_widgets
        Yast::UI.ChangeWidget(Id(:email), :Enabled, false)
        Yast::UI.ChangeWidget(Id(:reg_code), :Enabled, false)
      end

      # content for the main registration dialog
      # @return [Yast::Term]  UI term
      def content
        VBox(
          network_button,
          VStretch(),
          product_details_widgets,
          VSpacing(Yast::UI.TextMode ? 1 : 2),
          input_widgets,
          VSpacing(Yast::UI.TextMode ? 0 : 1),
          # button label
          PushButton(Id(:local_server), _("&Local Registration Server...")),
          VSpacing(Yast::UI.TextMode ? 0 : 3),
          skip_button,
          reregister_extensions_button,
          VStretch()
        )
      end

      # part of the main dialog definition - display the "skip" skip button only
      # when the system is not registered yet
      # @return [Yast::Term] UI term
      def skip_button
        # button label
        Registration.is_registered? ? Empty() : PushButton(Id(:skip), _("&Skip Registration"))
      end

      def reregister_extensions_button
        # display the addon re-registration button only in registered installed system
        return Empty() unless Registration.is_registered? && Yast::Mode.normal

        VBox(
          VSpacing(Yast::UI.TextMode ? 1 : 4),
          PushButton(Id(:reregister_addons), _("&Register Extensions or Modules Again"))
        )
      end

      # part of the main dialog definition - the base product details
      # @return [Yast::Term]  UI term
      def product_details_widgets
        HSquash(
          VBox(
            VSpacing(1),
            Left(Heading(SwMgmt.product_label(SwMgmt.find_base_product))),
            VSpacing(1),
            Registration.is_registered? ? Heading(_("The system is already registered.")) :
              Label(info)
          )
        )
      end

      # part of the main dialog definition - the input fields
      # @return [Yast::Term] UI term
      def input_widgets
        options = Storage::InstallationOptions.instance

        HSquash(
          VBox(
            MinWidth(REG_CODE_WIDTH, InputField(Id(:email), _("&E-mail Address"), options.email)),
            VSpacing(Yast::UI.TextMode ? 0 : 0.5),
            MinWidth(REG_CODE_WIDTH, InputField(Id(:reg_code), _("Registration &Code"),
              options.reg_code))
          )
        )
      end

      # help text for the main registration dialog
      def help_text
        # help text
        _("Enter SUSE Customer Center credentials here to register the system to " \
            "get updates and extensions.")
      end

      # the main UI event loop
      # @return [Symbol] the user input
      def handle_dialog
        ret = nil
        continue_buttons = [:next, :back, :cancel, :abort, :skip, :reregister_addons]

        until continue_buttons.include?(ret)
          ret = Yast::UI.UserInput

          case ret
          when :network
            Helpers.run_network_configuration
          when :local_server
            handle_local_server
          when :next
            ret = handle_registration
          when :abort
            ret = nil unless Yast::Mode.normal || AbortConfirmation.run
          when :skip
            ret = nil unless confirm_skipping
          end
        end

        log.info "Registration result: #{ret}"
        ret
      end

      # ask the user to confirm skipping the registration
      # @return [Boolean] true when skipping has been confirmed
      def confirm_skipping
        # Popup question: confirm skipping the registration
        confirmation = _("If you do not register your system we will not be able\n" \
            "to grant you access to the update repositories.\n\n" \
            "You can register after the installation or visit our\n" \
            "Customer Center for online registration.\n\n" \
            "Really skip the registration now?")

        ret = Yast::Popup.YesNo(confirmation)
        log.info "Skipping registration on user request" if ret

        ret
      end

      # description text displayed in the main dialog (kind of help text)
      # @return [String] translated description text
      def info
        # label text describing the registration (1/2)
        # use \n to split to more lines if needed (use max. 76 chars/line)
        info = _("Please enter a registration or evaluation code for this product and your\n" \
            "User Name/E-mail address from the SUSE Customer Center in the fields below.\n" \
            "Access to security and general software updates is only possible on\n" \
            "a registered system.")

        if !Yast::Mode.normal
          # add a paragraph separator
          info += "\n\n"

          # label text describing the registration (2/2),
          # not displayed in installed system
          # use \n to split to more lines if needed (use max. 76 chars/line)
          info += _("If you skip product registration now, remember to register after\n" \
              "installation has completed.")
        end

        info
      end

      # UI term for the network configuration button (or empty if not needed)
      # @return [Yast::Term] UI term
      def network_button
        return Empty() unless Helpers.network_configurable

        Right(PushButton(Id(:network), _("Network Configuration...")))
      end

      # handle pressing the "Local Registration Server" button
      def handle_local_server
        options = Storage::InstallationOptions.instance
        current_url = options.custom_url || SUSE::Connect::Config.new.url
        url = LocalServerDialog.run(current_url)
        return unless url

        log.info "Entered custom URL: #{url}"
        options.custom_url = url
      end

      # run the registration
      # @return [Symbol] symbol for the next workflow step (depending on the registration result)
      def handle_registration
        # do not re-register during installation
        if !Yast::Mode.normal && Registration.is_registered? &&
            Storage::InstallationOptions.instance.base_registered

          return :next
        end

        return nil if init_registration == :cancel

        if register_system_and_base_product
          store_registration_status
          return :next
        else
          reset_registration
          return nil
        end
      end

      # run the system and the base product registration
      # @return [Boolean] true on success
      def register_system_and_base_product
        registration_ui = RegistrationUI.new(registration)
        store_credentials

        success, product_service = registration_ui.register_system_and_base_product

        if product_service && !registration_ui.install_updates?
          registration_ui.disable_update_repos(product_service)
        end

        success
      end

      # remember the entered values in case user goes back
      def store_credentials
        options = Storage::InstallationOptions.instance
        options.email = Yast::UI.QueryWidget(:email, :Value)
        options.reg_code = Yast::UI.QueryWidget(:reg_code, :Value)
      end

      # store the successful registration
      def store_registration_status
        Storage::InstallationOptions.instance.base_registered = true
        # save the config if running in installed system
        # (in installation/upgrade it's written in _finish client)
        Helpers.write_config if Yast::Mode.normal
      end

      # reset the registration status when registration fails
      def reset_registration
        log.info "registration failed, resetting the registration URL"
        # reset the registration object and the cache to allow changing the URL
        self.registration = nil
        UrlHelpers.reset_registration_url
        Helpers.reset_registration_status
      end

      # initialize the Registration object
      # @return [Symbol, nil] returns :cancel if the URL selection was canceled
      def init_registration
        return if registration

        url = UrlHelpers.registration_url
        return :cancel if url == :cancel
        log.info "Initializing registration with URL: #{url.inspect}"
        self.registration = Registration.new(url)
      end
    end
  end
end
