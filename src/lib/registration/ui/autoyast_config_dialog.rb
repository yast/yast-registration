
require "yast"

require "registration/fingerprint"

module Registration
  module UI
    # this class displays and runs the main dialog for AutoYaST configuration
    class AutoyastConfigDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Popup"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Label"

      # list of widget ID in the dialog, add the new widget ID here after
      # adding a new widget to the dialog
      ALL_WIDGETS = [
        :addons, :do_registration, :email, :install_updates,
        :reg_code, :reg_server, :reg_server_cert, :reg_server_cert_fingerprint,
        :reg_server_cert_fingerprint_type, :slp_discovery
      ].freeze

      # widgets containing data (serialized to the exported Hash)
      # (:addons belongs to a push button, it does not contain any data)
      DATA_WIDGETS = ALL_WIDGETS - [:addons]

      # widgets which should react on the global on/off state
      # (exclude the the on/off checkbox itself)
      STATUS_WIDGETS = ALL_WIDGETS - [:do_registration]

      # display and run the dialog for configuring AutoYaST registration
      # @param config [Registration::Storage::Config] AutoYaST configuration
      # @return [Symbol] the user input
      def self.run(config)
        dialog = AutoyastConfigDialog.new(config)
        dialog.run
      end

      # the constructor
      # @param config [Registration::Storage::Config] AutoYaST configuration
      def initialize(config)
        textdomain "registration"

        @config = config
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        caption = _("Product Registration")
        help_text = "<p><b>#{caption}</b></p>"
        help_text += _(
          "<p>Product registration includes your product in SUSE Customer " \
            "Center database,\nenabling you to get online updates and " \
            "technical support.\nTo register while installing automatically, " \
            "select <b>Run Product Registration</b>.</p>"
        )
        help_text += _(
          "<p>If your network deploys a custom registration server, set the " \
          "correct URL of the server\nand the location of the SMT " \
          "certificate in <b>SMT Server Settings</b>. Refer\nto your SMT " \
          "manual for further assistance.</p>"
        )

        # FIXME: the dialog should be created by external code before calling this
        Wizard.CreateDialog
        Wizard.SetContents(caption, content, help_text, false, true)
        Wizard.SetNextButton(:next, Label.FinishButton)

        refresh_widget_state

        ret = handle_dialog

        Wizard.RestoreNextButton

        ret
      end

    private

      attr_reader :config

      # the UI defition for the global registration status
      # @return [Yast::Term] UI term
      def content_reg_settings
        VBox(
          Left(
            CheckBox(Id(:do_registration), Opt(:notify), _("Register the Product"),
              config.do_registration)
          )
        )
      end

      # the UI defition for the system registration credentials
      # @return [Yast::Term] UI term
      def content_reg_code_settings
        VBox(
          # Translators: Text for UI Label - capitalized
          Frame(_("Registration"),
            VBox(
              MinWidth(32, InputField(Id(:email), _("&E-mail Address"), config.email)),
              VSpacing(0.4),
              MinWidth(32, InputField(Id(:reg_code), _("Registration &Code"),
                config.reg_code)),
              VSpacing(0.4),
              Left(CheckBox(Id(:install_updates),
                _("Install Available Updates from Update Repositories"),
                config.install_updates))
            ))
        )
      end

      # the UI defition for the registration server options
      # @return [Yast::Term] UI term
      def content_server_settings
        sha1   = ::Registration::Fingerprint::SHA1
        sha256 = ::Registration::Fingerprint::SHA256
        fingerprint_type = (config.reg_server_cert_fingerprint_type || "").upcase

        VBox(
          # Translators: Text for UI Label - capitalized
          Frame(_("Server Settings"),
            VBox(
              VSpacing(0.2),
              Left(CheckBox(Id(:slp_discovery), Opt(:notify),
                _("Find Registration Server Using SLP Discovery"),
                config.slp_discovery)),
              VSpacing(0.4),
              # Translators: Text for UI Label - capitalized
              InputField(Id(:reg_server), Opt(:hstretch),
                _("Use Specific Server URL Instead of the Default"),
                config.reg_server),
              VSpacing(0.4),
              # Translators: Text for UI Label - capitalized
              InputField(
                Id(:reg_server_cert),
                Opt(:hstretch),
                _("Optional SSL Server Certificate URL"),
                config.reg_server_cert
              ),
              VSpacing(0.4),
              Left(
                ComboBox(
                  Id(:reg_server_cert_fingerprint_type),
                  Opt(:notify),
                  # Translators: Text for UI Label - capitalized
                  _("Optional SSL Server Certificate Fingerprint"),
                  [
                    Item(Id(""), _("none"),
                      fingerprint_type != sha1 && fingerprint_type != sha256),
                    Item(Id(sha1), sha1, fingerprint_type == sha1),
                    Item(Id(sha256), sha256, fingerprint_type == sha256)
                  ]
                )
              ),
              InputField(
                Id(:reg_server_cert_fingerprint),
                Opt(:hstretch),
                # Translators: Text for UI Label - capitalized
                _("SSL Certificate Fingerprint"),
                config.reg_server_cert_fingerprint
              )
            ))
        )
      end

      # the UI defition for the main dialog
      # @return [Yast::Term] UI term
      def content
        extra_spacing = Yast::UI.TextMode ? 0 : 1
        VBox(
          VSpacing(extra_spacing),
          content_reg_settings,
          HBox(
            HSpacing(2),
            VBox(
              VSpacing(extra_spacing),
              content_reg_code_settings,
              VSpacing(extra_spacing),
              content_server_settings,
              VSpacing(0.4),
              PushButton(Id(:addons), _("Register Extensions or Modules...")),
              VSpacing(0.4)
            )
          )
        )
      end

      # update widget states (enabled/disabled) according to the current status
      def refresh_widget_state
        enabled = Yast::UI.QueryWidget(Id(:do_registration), :Value)

        # global on/off handling
        STATUS_WIDGETS.each do |w|
          Yast::UI.ChangeWidget(Id(w), :Enabled, enabled)
        end

        # handle specific widgets
        slp_enabled = Yast::UI.QueryWidget(Id(:slp_discovery), :Value)
        Yast::UI.ChangeWidget(Id(:reg_server), :Enabled, !slp_enabled && enabled)

        fingeprint_enabled = Yast::UI.QueryWidget(Id(:reg_server_cert_fingerprint_type),
          :Value) != :none

        Yast::UI.ChangeWidget(Id(:reg_server_cert_fingerprint), :Enabled,
          fingeprint_enabled && enabled)
      end

      # store the config data
      def store_config
        data = DATA_WIDGETS.map do |w|
          [w.to_s, Yast::UI.QueryWidget(Id(w), :Value)]
        end

        import_data = Hash[data]
        # keep the current addons
        import_data["addons"] = config.addons
        config.import(import_data)
      end

      # the main UI even loop
      # @return [Symbol] the user input
      def handle_dialog
        ret = nil

        loop do
          ret = Yast::UI.UserInput
          log.info "ret: #{ret}"

          case ret
          when :do_registration, :slp_discovery, :reg_server_cert_fingerprint_type
            refresh_widget_state
          when :abort, :cancel
            break if Popup.ReallyAbort(true)
          when :next
            # FIXME: input validation
            break
          when :back, :addons
            break
          end
        end

        store_config if ret == :next || ret == :addons

        ret
      end
    end
  end
end
