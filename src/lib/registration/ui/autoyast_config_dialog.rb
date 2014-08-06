
require "yast"

module Registration
  module UI

    class AutoyastConfigDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Popup"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Label"

      # create a new dialog for accepting importing a SSL certificate and run it
      def self.run(config)
        dialog = AutoyastConfigDialog.new(config)
        dialog.run
      end

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
          "<p>Product registration includes your product in SUSE Customer Center database,\n"+
            "enabling you to get online updates and technical support.\n"+
            "To register while installing automatically, select <b>Run Product Registration</b>.</p>"
        )
        help_text += _(
          "<p>If your network deploys a custom registration server, set the correct URL of the server\n" +
            "and the location of the SMT certificate in <b>SMT Server Settings</b>. Refer\n" +
            "to your SMT manual for further assistance.</p>"
        )

        #FIXME
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

      def content_reg_settings
        VBox(
          Left(
            CheckBox(Id(:do_registration), Opt(:notify), _("Register the Product"),
              config.do_registration)
          )
        )
      end

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
            )
          )
        )
      end

      def content_server_settings
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
                      config.reg_server_cert_fingerprint_type != "SHA1" &&
                        config.reg_server_cert_fingerprint_type != "SHA256"),
                    Item(Id("SHA1"), "SHA1", config.reg_server_cert_fingerprint_type == "SHA1"),
                    Item(Id("SHA256"), "SHA256", config.reg_server_cert_fingerprint_type == "SHA256")
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
            )
          )
        )
      end

      def content
        VBox(
          VSpacing(1),
          content_reg_settings,
          HBox(
            HSpacing(2),
            VBox(
              VSpacing(1),
              content_reg_code_settings,
              VSpacing(1),
              content_server_settings,
              VSpacing(0.4),
              PushButton(Id(:addons), _("Register Extensions or Modules...")),
              VSpacing(0.4)
            )
          )
        )
      end

      def refresh_widget_state
        enabled = Yast::UI.QueryWidget(Id(:do_registration), :Value)
        all_widgets = [ :reg_server_cert, :email, :reg_code, :slp_discovery,
          :install_updates, :addons, :reg_server_cert_fingerprint_type,
          :reg_server_cert_fingerprint ]

        all_widgets.each do |w|
          Yast::UI.ChangeWidget(Id(w), :Enabled, enabled)
        end

        slp_enabled = Yast::UI.QueryWidget(Id(:slp_discovery), :Value)
        Yast::UI.ChangeWidget(Id(:reg_server), :Enabled, !slp_enabled && enabled)

        fingeprint_enabled = Yast::UI.QueryWidget(Id(:reg_server_cert_fingerprint_type), :Value) != :none
        Yast::UI.ChangeWidget(Id(:reg_server_cert_fingerprint), :Enabled, fingeprint_enabled && enabled)
      end

      def store_config
        data_widgets = [ :do_registration, :reg_server, :reg_server_cert,
          :email, :reg_code, :slp_discovery, :install_updates,
          :reg_server_cert_fingerprint_type, :reg_server_cert_fingerprint
        ]

        data = data_widgets.map do |w|
          [w.to_s, Yast::UI.QueryWidget(Id(w), :Value)]
        end

        import_data = Hash[data]
        # keep the current addons
        import_data["addons"] = config.addons
        config.import(import_data)
      end

      def handle_dialog
        begin
          ret = Yast::UI.UserInput
          log.info "ret: #{ret}"

          case ret
          when :do_registration, :slp_discovery, :reg_server_cert_fingerprint_type
            refresh_widget_state
          when :abort, :cancel
            break if Popup.ReallyAbort(true)
          when :next
            # TODO FIXME: input validation
          end
        end until ret == :next || ret == :back || ret == :addons

        store_config if ret == :next || ret == :addons

        ret
      end

    end
  end
end

