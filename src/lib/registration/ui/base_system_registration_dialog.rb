
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

      # @return [Symbol] Current action (:register_scc, :register_local or :skip_registration)
      attr_reader :action

      Yast.import "Mode"
      Yast.import "GetInstArgs"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Popup"

      WIDGETS = {
        register_scc: [:email, :reg_code],
        register_local: [:custom_url],
        skip_registration: []
      }
      private_constant :WIDGETS

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
        log.info "Displaying registration dialog"

        Yast::Wizard.SetContents(
          # dialog title
          _("Registration"),
          content,
          help_text,
          Yast::GetInstArgs.enable_back || (Yast::Mode.normal && Registration.is_registered?),
          Yast::GetInstArgs.enable_next || Yast::Mode.normal
        )

        # Set default action
        self.action = initial_action
        set_focus

        event_loop
      end

      # Set the initial action
      #
      # * If the system is registered:
      #   * using the default url -> :register_scc
      #   * using a custom URL -> :register_local
      # * If the system is not registered -> :register_scc
      #
      # @return [Symbol] Selected action
      def initial_action
        if Registration.is_registered?
          reg_options[:custom_url] == default_url ? :register_scc : :register_local
        else # Default option for unregistered systems
          :register_scc
        end
      end

      # Handle pushing the 'Next' button depending on the action
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

      # Handle pushing the 'Abort' button
      #
      # * In normal mode returns :abort
      # * In installation mode, ask for confirmation. If user
      #   confirms, returns :abort; nil otherwise.
      #
      # @return [Symbol,nil] :abort or nil
      # @see finish_di
      def abort_handler
        result = (Yast::Mode.normal || AbortConfirmation.run) ? :abort : nil
        finish_dialog(result) unless result.nil?
        result
      end

      # Handle selecting the 'Skip' option
      #
      # Set the dialog's action to :skip_registration
      def skip_registration_handler
        self.action = :skip_registration
      end

      # Handle selection the 'Register System via SCC.SUSE.COM' option
      #
      # Set the dialog's action to :register_scc
      def register_scc_handler
        self.action = :register_scc
      end

      # Handle selection the 'Register System via local SMT Server' option
      #
      # Set the dialog's action to :register_local
      def register_local_handler
        self.action = :register_local
      end

      # Handle pushing 'Network Configuration' button
      #
      # Runs the network configuration
      def network_handler
        Helpers.run_network_configuration
      end

      # Handle pushing the button to register again
      #
      # Just finish the dialog returning :reregister_addons
      def reregister_addons_handler
        finish_dialog(:reregister_addons)
      end

      # Handle pushing the 'Back' button
      def back_handler
        finish_dialog(:back)
      end

      attr_accessor :registration

    private

      # width of reg code input field widget
      REG_CODE_WIDTH = 33

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

      # Return registration options
      #
      # Read registration options from Storage::InstallationOptions
      # and, if needed, from Storage::RegCodes.
      #
      # @retun [Hash] Hash containing values for :reg_code,
      #               :email and :custom_url.
      def reg_options
        return @reg_options unless @reg_options.nil?
        options = Storage::InstallationOptions.instance

        reg_code = options.reg_code
        if reg_code.empty?
          known_reg_codes = Storage::RegCodes.instance.reg_codes
          base_product_name = SwMgmt.find_base_product["name"]
          reg_code = known_reg_codes[base_product_name] || ""
        end

        @reg_options = {
          reg_code: reg_code,
          email: options.email,
          custom_url: options.custom_url || default_url
        }
      end

      # Default registration server
      #
      # @return [String] URL for the registration server
      def default_url
        @default_url ||= SUSE::Connect::Config.new.url
      end

      def register_scc_option
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
                MinWidth(REG_CODE_WIDTH, InputField(Id(:email), _("&E-mail Address"), reg_options[:email])),
                VSpacing(Yast::UI.TextMode ? 0 : 0.5),
                MinWidth(REG_CODE_WIDTH, InputField(Id(:reg_code), _("Registration &Code"),
                reg_options[:reg_code]))
                )
              )
            ),
          VSpacing(1)
          )
      end

      def register_local_option
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
                MinWidth(REG_CODE_WIDTH, InputField(Id(:custom_url), _("&Local Registration Server URL"), reg_options[:custom_url]))
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
          options.custom_url = Yast::UI.QueryWidget(:custom_url, :Value)
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

      # Set dialog action
      #
      # @return [Symbol] Action (:register_scc, :register_local or :skip_registration)
      def action=(value)
        @action = value
        refresh
      end

      # Refresh widgets status depending on the current action
      #
      # @see #action
      def refresh
        # disable the input fields when already registered
        return disable_widgets if Registration.is_registered? && !Yast::Mode.normal

        WIDGETS.values.flatten.each do |wgt|
          Yast::UI.ChangeWidget(Id(wgt), :Enabled, WIDGETS[action].include?(wgt))
        end
        Yast::UI.ChangeWidget(Id(:action), :Value, action)
      end

      # Disable all input widgets
      def disable_widgets
        Yast::UI.ChangeWidget(Id(:action), :Enabled, false)
      end

      # Set focus
      #
      # The focus is set to the first widget of the current action.
      #
      # @see #action
      def set_focus
        widget = WIDGETS[action].first
        Yast::UI.SetFocus(Id(widget)) if widget
      end
    end
  end
end
