
require "yast"

module Registration
  module UI

    class AutoyastAddonDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Popup"
      Yast.import "UI"
      Yast.import "Wizard"

      # create a new dialog for accepting importing a SSL certificate and run it
      def self.run(addons)
        dialog = AutoyastAddonDialog.new(addons)
        dialog.run
      end

      def initialize(addons)
        textdomain "registration"

        @addons = addons
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        # help text
        help_text = _("<p>Here you can select which extensions or modules"\
            "will be registered together with the base product.</p>")

        Wizard.SetContents(_("Register Optional Extensions or Modules"), content,
          help_text, true, true)

        load_data

        handle_dialog
      end

      private

      attr_reader :addons

      def content
        header = Header(
          _("Identifier"),
          _("Version"),
          _("Architecture"),
          _("Release Type"),
          _("Registration Code")
        )

        VBox(
          Table(Id(:addons_table), header, []),
          HBox(
            PushButton(Id(:add), Label.AddButton),
            PushButton(Id(:edit), Label.EditButton),
            PushButton(Id(:delete), Label.DeleteButton),
            HSpacing(0.5),
            # button label
            PushButton(Id(:download),  _("Download Available Extensions...")
            ),
          )
        )
      end

      def load_data
        set_addon_table_content

        # disable download on a non-registered system
        Yast::UI.ChangeWidget(Id(:download), :Enabled, ::Registration::Registration.is_registered?)
      end

      def refresh_buttons
        enabled = !selected_addon.nil?
        Yast::UI.ChangeWidget(Id(:edit), :Enabled, enabled)
        Yast::UI.ChangeWidget(Id(:delete), :Enabled, enabled)
      end

      def handle_dialog
        begin
          refresh_buttons

          ret = Yast::UI.UserInput
          log.info "ret: #{ret}"

          case ret
          when :add
            add_addon
          when :edit
            edit_addon
          when :delete
            delete_addon
          when :abort, :cancel
            break if Popup.ReallyAbort(true)
          end
        end until [ :next, :back, :download ].include?(ret)

        ret
      end

      def selected_addon
        current = Yast::UI.QueryWidget(Id(:addons_table), :CurrentItem)
        return nil unless current

        find_addon(current)
      end

      def find_addon(name)
        addons.find{|a| a["name"] == name}
      end

      def delete_addon
        addon = selected_addon
        if Popup.YesNo(_("Really delete '%s'?") % addon["name"])
          addons.delete(addon)
          set_addon_table_content
        end
      end

      def edit_addon
        addon = selected_addon
        ret = display_addon_popup(addon)

        if ret
          # replace the content
          addon.merge!(ret)
          set_addon_table_content(addon["name"])
        end
      end

      def add_addon
        ret = display_addon_popup
        if ret
          addon = find_addon(ret["name"])
          if addon
            addon["reg_code"] = ret["reg_code"]
          else
            addons << ret
          end
          set_addon_table_content(ret["name"])
        end
      end

      def set_addon_table_content(current = nil)
        content = addons.map do |a|
          Item(Id(a["name"]), a["name"], a["version"], a["arch"],
            a["release_type"],  a["reg_code"])
        end

        Yast::UI.ChangeWidget(Id(:addons_table), :Items, content)
        Yast::UI.ChangeWidget(Id(:addons_table), :CurrentItem, current) if current
      end

      def addon_popup_content(addon)
        VBox(
          InputField(Id(:name), _("Extension or Module &Identifier"), addon["name"] || ""),
          InputField(Id(:version), _("&Version"), addon["version"] || ""),
          InputField(Id(:arch), _("&Architecture"), addon["arch"] || ""),
          InputField(Id(:release_type), _("&Release Type"),
            # handle nil specifically, it cannot be stored in XML profile
            addon["release_type"] || "nil"),
          InputField(Id(:reg_code), _("Registration &Code"), addon["reg_code"] || ""),
          VSpacing(1),
          ButtonBox(
            PushButton(Id(:ok), Opt(:default), Label.OKButton),
            PushButton(Id(:cancel), Label.CancelButton)
          )
        )
      end

      def entered_addon
        release_type = Yast::UI.QueryWidget(Id(:release_type), :Value)
        release_type = nil if release_type == "nil"

        {
          "name" => Yast::UI.QueryWidget(Id(:name), :Value),
          "version" => Yast::UI.QueryWidget(Id(:version), :Value),
          "arch" => Yast::UI.QueryWidget(Id(:arch), :Value),
          "release_type" => release_type,
          "reg_code" => Yast::UI.QueryWidget(Id(:reg_code), :Value)
        }
      end

      def display_addon_popup(addon = {})
        Yast::UI.OpenDialog(addon_popup_content(addon))

        begin
          ui = Yast::UI.UserInput

          ui == :ok ? entered_addon : nil
        ensure
          Yast::UI.CloseDialog
        end
      end

    end
  end
end
