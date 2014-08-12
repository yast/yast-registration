
require "yast"

module Registration
  module UI

    class AddonRegCodesDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Mode"
      Yast.import "GetInstArgs"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Stage"

      # create a new dialog for accepting importing a SSL certificate and run it
      def self.run(addons, known_reg_codes)
        dialog = AddonRegCodesDialog.new(addons, known_reg_codes)
        dialog.run
      end

      def initialize(addons, known_reg_codes)
        textdomain "registration"

        @addons = addons
        @known_reg_codes = known_reg_codes
      end

      # display the extension selection dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        Wizard.SetContents(
          # dialog title
          _("Extension and Module Registration Codes"),
          # display only the products which need a registration code
          content,
          # help text
          _("<p>Enter registration codes for the requested extensions or modules.</p>\n"\
              "<p>Registration codes are required for successfull registration." \
              "If you cannot provide a registration code then go back and deselect " \
              "the respective extension or module.</p>"),
          true,
          true
        )

        handle_dialog
      end

      private

      attr_reader :addons, :known_reg_codes

      # the maximum number of reg. codes displayed vertically,
      # this is the limit for 80x25 textmode UI
      MAX_REGCODES_PER_COLUMN = 8

      # width of reg code input field widget
      REG_CODE_WIDTH = 33

      def reg_code_boxes
        # display the second column if needed
        if addons_with_regcode.size > MAX_REGCODES_PER_COLUMN
          # display only the addons which fit two column layout
          display_addons = addons_with_regcode[0..2*MAX_REGCODES_PER_COLUMN - 1]

          # round the half up (more items in the first column for odd number of items)
          half = (display_addons.size + 1) / 2

          box1 = addon_regcode_items(display_addons[0..half - 1])
          box2 = HBox(
            HSpacing(2),
            addon_regcode_items(display_addons[half..-1])
          )
        else
          box1 = addon_regcode_items(addons_with_regcode)
          box2 = Empty()
        end

        [box1, box2]
      end

      def labels
        [
          Left(Label(n_(
                "The extension you selected needs a separate registration code.",
                "The extensions you selected need separate registration codes.",
                addons_with_regcode.size
              ))),
          Left(Label(n_(
                "Enter the registration code into the field below.",
                "Enter the registration codes into the fields below.",
                addons_with_regcode.size
              )))
        ]
      end

      def content
        HBox(
          HSpacing(Opt(:hstretch), 3),
          VBox(
            VStretch(),
            *labels,
            VStretch(),
            HBox(*reg_code_boxes),
            VStretch()
          ),
          HSpacing(Opt(:hstretch), 3)
        )
      end

      def addon_regcode_item(addon)
        MinWidth(REG_CODE_WIDTH, InputField(Id(addon.identifier),
            addon.label, known_reg_codes.fetch(addon.identifier, "")))
      end

      def addon_regcode_items(addons)
        # add extra spacing when there are just few addons, in GUI always
        extra_spacing = (addons.size < 5) || !Yast::UI.TextMode
        box = VBox()

        addons.each do |addon|
          box[box.size] = addon_regcode_item(addon)
          box[box.size] = VSpacing(1) if extra_spacing
        end

        box
      end

      def addons_with_regcode
        addons.reject(&:free)
      end

      # collect and update the entered reg codes from UI
      def collect_addon_regcodes
        pairs = addons_with_regcode.map do |a|
          [a.identifier, Yast::UI.QueryWidget(Id(a.identifier), :Value)]
        end
        known_reg_codes.merge!(Hash[pairs])
      end

      def handle_dialog
        continue_buttons = [:next, :back, :abort]

        ret = nil
        while !continue_buttons.include?(ret) do
          ret = Yast::UI.UserInput

          case ret
          when :next
            collect_addon_regcodes
          when :cancel, :abort
            ret = nil if Stage.initial && !Popup.ConfirmAbort(:painless)
            ret = :abort if ret == :cancel
          end
        end

        ret
      end

    end
  end
end

