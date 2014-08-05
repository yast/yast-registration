
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
          GetInstArgs.enable_back || Mode.normal || Mode.config,
          GetInstArgs.enable_next || Mode.normal || Mode.config
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

      def content
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
        end

        HBox(
          HSpacing(Opt(:hstretch), 3),
          VBox(
            VStretch(),
            Left(Label(n_(
                  "The extension you selected needs a separate registration code.",
                  "The extensions you selected need separate registration codes.",
                  addons_with_regcode.size
                ))),
            Left(Label(n_(
                  "Enter the registration code into the field below.",
                  "Enter the registration codes into the fields below.",
                  addons_with_regcode.size
                ))),
            VStretch(),
            HBox(
              box1,
              box2 ? box2 : Empty()
            ),
            VStretch()
          ),
          HSpacing(Opt(:hstretch), 3)
        )
      end

      def addon_regcode_items(addons)
        textmode = Yast::UI.TextMode
        box = VBox()

        addons.each do |addon|
          box[box.size] = MinWidth(REG_CODE_WIDTH, InputField(Id(addon.identifier),
              addon.label, known_reg_codes.fetch(addon.identifier, "")))
          # add extra spacing when there are just few addons, in GUI always
          box[box.size] = VSpacing(1) if (addons.size < 5) || !textmode
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
        continue_buttons = [:next, :back, :close, :abort]

        ret = nil
        while !continue_buttons.include?(ret) do
          ret = Yast::UI.UserInput

          collect_addon_regcodes if ret == :next
        end

        ret
      end

    end
  end
end
