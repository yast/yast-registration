
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

      # create a new dialog for accepting importing a SSL certificate and run it
      def self.run
        dialog = BaseSystemRegistrationDialog.new
        dialog.run
      end

      def initialize
        textdomain "registration"
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        Yast::Wizard.SetContents(
          # dialog title
          _("Registration"),
          content,
          help_text,
          Yast::GetInstArgs.enable_back,
          Yast::GetInstArgs.enable_next || Yast::Mode.normal
        )

        # disable the input fields when already registered
        if Registration.is_registered? && !Yast::Mode.normal
          Yast::UI.ChangeWidget(Id(:email), :Enabled, false)
          Yast::UI.ChangeWidget(Id(:reg_code), :Enabled, false)
        end

        handle_dialog
      end

      attr_accessor :registration

      private

      # width of reg code input field widget
      REG_CODE_WIDTH = 33

      # content for the main registration dialog
      def content
        options = Storage::InstallationOptions.instance
        registered = Registration.is_registered?

        VBox(
          network_button,
          VStretch(),
          HSquash(
            VBox(
              VSpacing(1),
              Left(Heading(SwMgmt.base_product_label(SwMgmt.find_base_product))),
              VSpacing(1),
              registered ? Heading(_("The system is already registered.")) : Label(info)
            )
          ),
          VSpacing(Yast::UI.TextMode ? 1 : 2),
          HSquash(
            VBox(
              MinWidth(REG_CODE_WIDTH, InputField(Id(:email), _("&E-mail Address"), options.email)),
              VSpacing(Yast::UI.TextMode ? 0 : 0.5),
              MinWidth(REG_CODE_WIDTH, InputField(Id(:reg_code), _("Registration &Code"),
                options.reg_code))
            )
          ),
          VSpacing(Yast::UI.TextMode ? 0 : 1),
          # button label
          PushButton(Id(:local_server), _("&Local Registration Server...")),
          VSpacing(Yast::UI.TextMode ? 0 : 3),
          # button label
          registered ? Empty() : PushButton(Id(:skip), _("&Skip Registration")),
          VStretch()
        )
      end

      # help text for the main registration dialog
      def help_text
        # help text
        _("Enter SUSE Customer Center credentials here to register the system to " \
            "get updates and extensions.")
      end

      def handle_dialog
        log.info "The system is not registered, diplaying registration dialog"

        ret = nil

        continue_buttons = [:next, :back, :cancel, :abort, :skip]
        until continue_buttons.include?(ret)
          ret = Yast::UI.UserInput

          case ret
          when :network
            Helpers.run_network_configuration
          when :local_server
            handle_local_server
          when :next
            # do not re-register during installation
            if !Yast::Mode.normal && Registration.is_registered? &&
                Storage::InstallationOptions.instance.base_registered

              return :next
            end

            next if init_registration == :cancel

            ret = handle_registration
          when :abort
            ret = nil unless Yast::Popup.ConfirmAbort(:painless)
          when :skip
            ret = nil unless confirm_skipping
          end
        end

        log.info "Registration result: #{ret}"
        ret
      end

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

      def network_button
        return Empty() unless Yast::Mode.installation || Yast::Mode.update

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

      def handle_registration
        options = Storage::InstallationOptions.instance

        # remember the entered values in case user goes back
        options.email = Yast::UI.QueryWidget(:email, :Value)
        options.reg_code = Yast::UI.QueryWidget(:reg_code, :Value)

        # reset the user input in case an exception is raised
        ret = nil

        registration_ui = RegistrationUI.new(registration)
        success, product_service =
          registration_ui.register_system_and_base_product(options.email,
            options.reg_code, register_base_product: !options.base_registered)

        if success
          if product_service && !registration_ui.install_updates?
            registration_ui.disable_update_repos(product_service)
          end

          ret = :next
          options.base_registered = true
          # save the config if running in installed system
          # (in installation/upgrade it's written in _finish client)
          Helpers.write_config if Yast::Mode.normal
        else
          log.info "registration failed, resetting the registration URL"
          # reset the registration object and the cache to allow changing the URL
          self.registration = nil
          UrlHelpers.reset_registration_url
          Helpers.reset_registration_status
        end

        ret
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
