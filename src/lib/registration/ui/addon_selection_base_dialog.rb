# Copyright (c) 2015 SUSE LINUX GmbH, Nuernberg, Germany.

require "yast"
require "registration/ui/abort_confirmation"
require "registration/addon"
require "registration/addon_sorter"
require "registration/sw_mgmt"

module Registration
  module UI
    # this class displays and runs the dialog with addon selection
    class AddonSelectionBaseDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "GetInstArgs"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Stage"
      Yast.import "Arch"

      class << self
        attr_accessor :filter_beta
      end

      FILTER_BETAS_INITIALLY = true

      # constructor
      # @param registration [Registration::Registration] use this Registration object for
      #   communication with SCC
      def initialize(registration)
        textdomain "registration"
        @all_addons = Addon.find_all(registration)

        # sort the addons
        @all_addons.sort!(&::Registration::ADDON_SORTER)

        self.class.filter_beta = FILTER_BETAS_INITIALLY if self.class.filter_beta.nil?

        filter_beta_releases(self.class.filter_beta)

        @old_selection = Addon.selected.dup

        # activate a workaround on ARM (FATE#320679)
        aarch64_workaround if Arch.aarch64

        log.info "Available addons: #{@all_addons}"
      end

      # reimplement this in a subclass
      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input
      def run
        raise "Not implemented"
      end

    protected

      # create widget ID for an addon
      # @param [<Addon>] addon the addon
      # @return [String] widget id
      def addon_widget_id(addon)
        "#{addon.identifier}-#{addon.version}-#{addon.arch}"
      end

      # Enables or disables beta addons filtering
      # @param [Boolean] enable true for filtering beta releases
      def filter_beta_releases(enable)
        self.class.filter_beta = enable
        if enable
          @addons, available_addons = @all_addons.partition(&:registered?)
          @addons.concat(available_addons.reject(&:beta_release?))
        else
          @addons = @all_addons
        end
      end

    private

      # reimplement this in a subclass
      # @return [String] dialog head
      def heading
        raise "Not implemented"
      end

      # reimplement this in a subclass
      # @return [Boolean] is the addon selected?
      def addon_selected?(_addon)
        raise "Not implemented"
      end

      # create the main dialog definition
      # @return [Yast::Term] the main UI dialog term
      def content
        check_filter = self.class.filter_beta.nil? ? FILTER_BETAS_INITIALLY : self.class.filter_beta
        VBox(
          Left(Heading(heading)),
          Left(CheckBox(Id(:filter_beta), Opt(:notify),
            _("&Filter Out Beta Versions"), check_filter)),
          addons_box,
          Left(Label(_("Details"))),
          details_widget
        )
      end

      # addon description widget
      # @return [Yast::Term] the addon details widget
      def details_widget
        MinHeight(8,
          VWeight(25, RichText(Id(:details), Opt(:disabled), "<small>" +
                _("Select an extension or a module to show details here") + "</small>")))
      end

      # @return [String] a Value for a RichText
      def addon_checkboxes
        @addons.map { |a| addon_checkbox(a) }.join("\n")
      end

      # @param [<Addon>] addon the addon
      # @return [String] a Value for a RichText
      def addon_checkbox(addon)
        # checkbox label for an unavailable extension
        # (%s is an extension name)
        label = addon.available? ? addon.label : (_("%s (not available)") % addon.label)
        richtext_checkbox(id:       addon_widget_id(addon),
                          label:    label,
                          selected: addon_selected?(addon),
                          enabled:  addon.selectable?,
                          indented: addon.depends_on)
      end

      IMAGE_DIR = "/usr/share/YaST2/theme/current/wizard".freeze
      IMAGES = {
        "normal:on:enabled"   => "checkbox-on.png",
        "normal:off:enabled"  => "checkbox-off.png",
        # theme has no special images for disabled checkboxes
        "normal:on:disabled"  => "checkbox-on.png",
        "normal:off:disabled" => "checkbox-off.png",
        "inst:on:enabled"     => "inst_checkbox-on.png",
        "inst:off:enabled"    => "inst_checkbox-off.png",
        "inst:on:disabled"    => "inst_checkbox-on-disabled.png",
        "inst:off:disabled"   => "inst_checkbox-off-disabled.png"
      }.freeze

      # Make a simulation of a CheckBox displayed in a RichText
      # @param id [String]
      # @param label [String]
      # @param selected [Boolean]
      # @param enabled [Boolean]
      # @param indented [Boolean]
      # @return [String] a Value for a RichText
      def richtext_checkbox(id:, label:, selected:, enabled:, indented: false)
        if Yast::UI.TextMode
          indent = "&nbsp;" * (indented ? 5 : 1)
          check = selected ? "[x]" : "[ ]"
          widget = "#{check} #{label}"
          enabled_widget = enabled ? "<a href=\"#{id}\">#{widget}</a>" : widget
          "#{indent}#{enabled_widget}<br>"
        else
          indent = "&nbsp;" * (indented ? 7 : 1)

          # check for installation style, which is dark, FIXME: find better way
          installation = ENV["Y2STYLE"] == "installation.qss"
          image = (installation ? "inst:" : "normal:") +
            (selected ? "on:" : "off:") + (enabled ? "enabled" : "disabled")
          color = installation ? "white" : "black"

          check = "<img src='#{IMAGE_DIR}/#{IMAGES[image]}'></img>"
          widget = "#{check} #{label}"
          enabled_widget = if enabled
            "<a href='#{id}' style='text-decoration:none; color:#{color}'>#{widget}</a>"
          else
            "<span style='color:grey'>#{widget}</span>"
          end
          "<p>#{indent}#{enabled_widget}</p>"
        end
      end

      # create UI box with addon check boxes
      # @return [Yast::Term] the main UI dialog term
      def addons_box
        content = RichText(Id(:items), addon_checkboxes)

        VWeight(75, MinHeight(12, content))
      end

      # the main event loop - handle the user in put in the dialog
      # @return [Symbol] the user input
      def handle_dialog
        Yast::UI.SetFocus(Id(:items))

        ret = nil
        continue_buttons = [:next, :back, :abort, :skip]

        until continue_buttons.include?(ret)
          ret = Yast::UI.UserInput

          case ret
          when :next
            ret = handle_next_button
          when :cancel, :abort
            ret = Stage.initial && !AbortConfirmation.run ? nil : :abort
            # when canceled switch to old selection
            Addon.selected.replace(@old_selection) if ret == :abort
          when :filter_beta
            filter_beta_releases(Yast::UI.QueryWidget(Id(ret), :Value))
            show_addons
          else
            handle_addon_selection(ret)
          end
        end

        ret
      end

      # handler for the :next button in the main loop
      def handle_next_button
        return nil unless supported_addon_count?

        log.info "Selected addons: #{Addon.selected.map(&:name)}"

        Addon.selected.empty? ? :skip : :next
      end

      # handler for changing the addon status in the main loop
      # @param id [String] addon widget id
      def handle_addon_selection(id)
        # check whether it's an add-on ID (checkbox clicked)
        addon = @addons.find { |a| addon_widget_id(a) == id }
        return unless addon

        addon.toggle_selected
        show_addon_details(addon)
        show_addons
      end

      # update addon details after changing the current addon in the UI
      # @param addon []
      def show_addon_details(addon)
        # addon description is a rich text
        Yast::UI.ChangeWidget(Id(:details), :Value, addon.description)
        Yast::UI.ChangeWidget(Id(:details), :Enabled, true)
      end

      # show the addon list when some are filtered, enabled, selected
      def show_addons
        Yast::UI.ChangeWidget(Id(:items), :Value, addon_checkboxes)
      end

      # the maximum number of reg. codes displayed vertically,
      # this is the limit for 80x25 textmode UI
      MAX_REGCODES_PER_COLUMN = 8

      # check the number of required reg. codes
      # @return [Boolean] true if the number of the required reg. codes fits
      #  the maximum limit
      def supported_addon_count?
        # maximum number or reg codes which can be displayed in two column layout
        max_supported = 2 * MAX_REGCODES_PER_COLUMN

        # check if the count of addons requiring a reg. code fits two columns
        if Addon.selected.count { |a| a.registered? && a.free } > max_supported
          Report.Error(_("YaST allows to select at most %s extensions or modules.") % max_supported)
          return false
        end

        true
      end

      # shared part of the help text
      # @return [String] translated help text
      def generic_help_text
        # help text (2/3)
        _("<p>Please note, that some extensions or modules might need "\
            "specific registration code.</p>") +
          # help text (3/3)
          _("<p>If you want to remove any extension or module you need to log"\
              "into the SUSE Customer Center and remove them manually there.</p>")
      end

      # workaround for FATE#320679 - preselect the Toolchain module on ARM
      # in SLES12-SP2
      # FIXME: remove this hack in SLES12-SP3, use a proper solution instead
      def aarch64_workaround
        # SLES12-SP2 base?
        product = SwMgmt.base_product_to_register
        return unless product["name"] == "SLES" && product["version"] == "12.2"

        # is the Toolchain module available?
        toolchain = @addons.find do |addon|
          addon.identifier == "sle-module-toolchain" && addon.version == "12" \
            && addon.arch == "aarch64"
        end
        return unless toolchain

        # then pre-select it!
        log.info "Activating the ARM64 workaround, preselecting addon: #{toolchain}"
        toolchain.selected
      end
    end
  end
end
