
require "yast"

module Registration
  module UI
    # this class displays and runs the dialog for cofiguring addons in AutoYast mode
    # FIXME: use a specific class instead of Hash for AutoYast addons
    class AutoyastAddonDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Popup"
      Yast.import "UI"
      Yast.import "Wizard"

      # display and run the dialog for configuring AutoYaST addons
      # @param addons [Hash] list of configured addons
      # @return [Symbol] the user input
      def self.run(addons)
        dialog = AutoyastAddonDialog.new(addons)
        dialog.run
      end

      # the constructor
      # @param addons [Hash] list of configured addons
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

      # create the main dialog content
      # @return [Yast::Term] UI definition
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
            PushButton(Id(:download), _("Download Available Extensions...")
            )
          )
        )
      end

      # fill the displayed dialog with data
      def load_data
        set_addon_table_content

        # disable download on a non-registered system
        Yast::UI.ChangeWidget(Id(:download), :Enabled, ::Registration::Registration.is_registered?)
      end

      # enable Edit/Delete buttons if an addon is selected
      def refresh_buttons
        enabled = !selected_addon.nil?
        Yast::UI.ChangeWidget(Id(:edit), :Enabled, enabled)
        Yast::UI.ChangeWidget(Id(:delete), :Enabled, enabled)
      end

      # the main event loop
      # @return [Symbol] the user input
      def handle_dialog
        loop do
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
          when :next, :back, :download
            break
          end
        end

        ret
      end

      # find the selected addon in the table
      def selected_addon
        current = Yast::UI.QueryWidget(Id(:addons_table), :CurrentItem)
        return nil unless current

        find_addon(current)
      end

      # find addon by name
      # @param name [String] addon name
      # @return [Hash,nil] the addon or nil if not found
      def find_addon(name)
        addons.find { |a| a["name"] == name }
      end

      # remove the selected addon after user confirms the removal
      def delete_addon
        addon = selected_addon
        return unless Popup.YesNo(_("Really delete '%s'?") % addon["name"])

        addons.delete(addon)
        set_addon_table_content
      end

      # display edit dialog and update the addon
      def edit_addon
        addon = selected_addon
        ret = display_addon_popup(addon)
        return unless ret

        # replace the content
        addon.merge!(ret)
        set_addon_table_content(addon["name"])
      end

      # display add addon popup, add the user added addon
      def add_addon
        ret = display_addon_popup
        return unless ret

        addon = find_addon(ret["name"])

        if addon
          addon["reg_code"] = ret["reg_code"]
        else
          addons << ret
        end

        set_addon_table_content(ret["name"])
      end

      # update addons in the table
      def set_addon_table_content(current = nil)
        content = addons.map do |a|
          Item(Id(a["name"]), a["name"], a["version"], a["arch"],
            a["release_type"], a["reg_code"])
        end

        Yast::UI.ChangeWidget(Id(:addons_table), :Items, content)
        Yast::UI.ChangeWidget(Id(:addons_table), :CurrentItem, current) if current
      end

      # dialog definition for adding/editing an addon
      # @return [Yast::Term] popup definition
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

      # read the user values from popup and create a addon config
      # @see #addon_popup_content
      # @return [Hash] addon config
      def entered_addon
        release_type = Yast::UI.QueryWidget(Id(:release_type), :Value)
        release_type = nil if release_type == "nil"

        {
          "name"         => Yast::UI.QueryWidget(Id(:name), :Value),
          "version"      => Yast::UI.QueryWidget(Id(:version), :Value),
          "arch"         => Yast::UI.QueryWidget(Id(:arch), :Value),
          "release_type" => release_type,
          "reg_code"     => Yast::UI.QueryWidget(Id(:reg_code), :Value)
        }
      end

      # display popup with the specified addon
      # @return [Hash,nil] the addon entered by user or nil if canceled
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
