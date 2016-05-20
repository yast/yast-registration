
require "yast"
require "yast/suse_connect"
require "ui/event_dispatcher"

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
      include ::UI::EventDispatcher

      attr_accessor :action

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

        # Set default action
        self.action = :register_scc
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        log.info "Displaying registration dialog"

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

        event_loop
      end

      # Handle pushing the :next button depending on the action
      #
      # When action is:
      #
      # * :skip_registration: returns :skip to skip the registration process.
      # * :register_scc o :register_local: calls #handle_registration
      #
      # @return [Symbol,nil]
      #
      # @see #handle_registration
      def next_handler
        result =
          case action
          when :skip_registration
            confirm_skipping ? :skip : nil
          when :register_scc, :register_local
            handle_registration
          end
        finish_dialog(result) unless result.nil?
        result
      end

      # :abort action handler
      #
      # * In normal mode returns :abort
      # * In installation mode, ask for confirmation. If user
      #   confirms, returns :abort; nil otherwise.
      #
      # @return [Symbol,nil] :abort or nil
      def abort_handler
        result = (Yast::Mode.normal || AbortConfirmation.run) ? :abort : nil
        finish_dialog(result)
        result
      end

      # :skip_registration handler
      #
      # Set the dialog's action to :skip_registration
      def skip_registration_handler
        self.action = :skip_registration
      end

      # :register_scc handler
      #
      # Set the dialog's action to :register_scc
      def register_scc_handler
        self.action = :register_scc
      end

      # :register_local handler
      #
      # Set the dialog's action to :register_local
      def register_local_handler
        self.action = :register_local
      end

      # :network handler
      #
      # Runs the network configuration
      def network_handler
        Helpers.run_network_configuration
      end

      # :reregister_addons handler
      #
      # Just finish the dialog returning :reregister_addons
      def reregister_addons_handler
        finish_dialog(:reregister_addons)
      end

      # :back handler
      def back_handler
        finish_dialog(:back)
      end

      attr_accessor :registration

    private

      # width of reg code input field widget
      REG_CODE_WIDTH = 33

      def disable_widgets
        Yast::UI.ChangeWidget(Id(:action), :Enabled, false)
      end

      # content for the main registration dialog
      # @return [Yast::Term]  UI term
      def content
        VBox(
          network_button,
          VStretch(),
          product_details_widgets,
          VSpacing(Yast::UI.TextMode ? 1 : 2),
          registration_widgets,
          VSpacing(Yast::UI.TextMode ? 0 : 3),
          reregister_extensions_button,
          VStretch()
        )
      end

      def registration_widgets
        HSquash(
          VBox(
            RadioButtonGroup(
              Id(:action),
              VBox(
                register_scc_option,
                register_local_option,
                skip_option
              )
            )
          )
        )
      end

      def register_scc_option
        options = Storage::InstallationOptions.instance

        reg_code = options.reg_code
        if reg_code.empty?
          known_reg_codes = Storage::RegCodes.instance.reg_codes
          base_product_name = SwMgmt.find_base_product["name"]
          reg_code = known_reg_codes[base_product_name] || ""
        end

        # FIXME: it should be in a different method responsible for handling the UI
        VBox(
          Left(
            RadioButton(
              Id(:register_scc),
              Opt(:notify),
              # TRANSLATORS: radio button
              _("Register System via SCC.SUSE.COM"),
              action == :register_scc
              )
            ),
          VSpacing(0.3),
          Left(
            HBox(
              HSpacing(5),
              VBox(
                MinWidth(REG_CODE_WIDTH, InputField(Id(:email), _("&E-mail Address"), options.email)),
                VSpacing(Yast::UI.TextMode ? 0 : 0.5),
                MinWidth(REG_CODE_WIDTH, InputField(Id(:reg_code), _("Registration &Code"),
                reg_code))
                )
              )
            ),
          VSpacing(1)
          )
      end

      def register_local_option
        options = Storage::InstallationOptions.instance
        custom_url = options.custom_url || SUSE::Connect::Config.new.url

        # FIXME: it should be in a different method responsible for handling the UI
        VBox(
          Left(
            RadioButton(
              Id(:register_local),
              Opt(:notify),
              # TRANSLATORS: radio button
              _("Register System via local SMT Server"),
              action == :register_local
              )
            ),
          VSpacing(0.3),
          Left(
            HBox(
              HSpacing(5),
              VBox(
                MinWidth(REG_CODE_WIDTH, InputField(Id(:smt_url), _("&Local Registration Server URL"), custom_url))
                )
              )
            ),
          VSpacing(1)
          )
      end

      def skip_option
        return Empty() if Registration.is_registered?
        Left(
          RadioButton(
            Id(:skip_registration),
            Opt(:notify),
            _("&Skip Registration"),
            action == :skip_registration
          )
        )
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

      # help text for the main registration dialog
      def help_text
        # help text
        _("Enter SUSE Customer Center credentials here to register the system to " \
            "get updates and extensions.")
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
        info = _("Please select your preferred method of registration.")

        if !Yast::Mode.normal
          # add a paragraph separator
          info += "\n"

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

        Right(PushButton(Id(:network), _("Net&work Configuration...")))
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
        set_registration_options

        success, product_service = registration_ui.register_system_and_base_product

        if product_service && !registration_ui.install_updates?
          registration_ui.disable_update_repos(product_service)
        end

        success
      end

      # Set registration options according to current action
      #
      # When current action is:
      #
      # * :register_scc -> set email and registration code
      # * :register_local -> set custom url
      def set_registration_options
        options = Storage::InstallationOptions.instance
        case action
        when :register_scc
          options.email = Yast::UI.QueryWidget(:email, :Value)
          options.reg_code = Yast::UI.QueryWidget(:reg_code, :Value)
        when :register_local
          options.custom_url = Yast::UI.QueryWidget(:smt_url, :Value)
        else
          raise "Unknown action: #{action}"
        end
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
