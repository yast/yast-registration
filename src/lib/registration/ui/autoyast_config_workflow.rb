
require "yast"
require "registration/helpers"
require "registration/connect_helpers"
require "registration/url_helpers"

require "registration/ui/autoyast_addon_dialog"
require "registration/ui/autoyast_config_dialog"
require "registration/ui/addon_selection_dialog"
require "registration/ui/addon_eula_dialog"
require "registration/ui/addon_reg_codes_dialog"

module Registration
  module UI
    # this class runs the AutoYast configuration workflow
    class AutoyastConfigWorkflow
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Pkg"
      Yast.import "Report"
      Yast.import "Sequencer"

      # run the AutoYast configuration workflow
      # @param config [Registration::Storage::Config] AutoYaST configuration
      def self.run(config)
        workflow = AutoyastConfigWorkflow.new(config)
        workflow.run
      end

      # constructor
      # @param config [Registration::Storage::Config] AutoYaST configuration
      def initialize(config)
        textdomain "registration"

        @config = config
      end

      # run the workflow
      # @return [Symbol] the user input
      def run
        aliases = {
          "general"         => ->() { configure_registration },
          "addons"          => [->() { select_addons }, true],
          "remote_addons"   => [->() { select_remote_addons }, true],
          "addons_eula"     => [->() { addons_eula }, true],
          "addons_regcodes" => [->() { addons_reg_codes }, true]
        }

        sequence = {
          "ws_start"        => "general",
          "general"         => {
            abort:  :abort,
            next:   :next,
            addons: "addons"
          },
          "addons"          => {
            abort:    :abort,
            next:     "general",
            download: "remote_addons"
          },
          "remote_addons"   => {
            addons: "addons",
            abort:  :abort,
            next:   "addons_eula"
          },
          "addons_eula"     => {
            abort: :abort,
            next:  "addons_regcodes"
          },
          "addons_regcodes" => {
            abort: :abort,
            next:  "addons"
          }
        }

        log.info "Starting scc_auto sequence"
        Sequencer.Run(aliases, sequence)
      end

      private

      attr_reader :config

      # run the dialog configuring the AutoYaST addons
      # @return [Symbol] the user input
      def select_addons
        AutoyastAddonDialog.run(config.addons)
      end

      # download the addons from SCC, let the user select addons to install
      # @return [Symbol] the user input
      def select_remote_addons
        if !SwMgmt.init
          Report.Error(Pkg.LastError)
          return :abort
        end

        url = UrlHelpers.registration_url
        registration = ::Registration::Registration.new(url)

        ret = nil

        success = ConnectHelpers.catch_registration_errors do
          Popup.Feedback(
            SccAutoClient::CONTACTING_MESSAGE,
            _("Loading Available Extensions and Modules...")) do
            # reset registration status to allow selecting all addons
            ::Registration::Addon.find_all(registration).each(&:unregistered)
          end

          ret = AddonSelectionDialog.run(registration)
        end

        success ? ret : :addons
      end

      # display the EULAs for the selected addons
      # @return [Symbol] the user input
      def addons_eula
        AddonEulaDialog.run(::Registration::Addon.selected)
      end

      # collect the known reg. codes from the current configuration
      # @return [Hash] reg. codes hash
      def collect_known_reg_codes
        Hash[config.addons.map { |a| [a["name"], a["reg_code"]] }]
      end

      # add for reg. codes for selected paid extensions
      # @return [Symbol] the user input
      def addons_reg_codes
        known_reg_codes = collect_known_reg_codes

        if !::Registration::Addon.selected.all?(&:free)
          ret = AddonRegCodesDialog.run(::Registration::Addon.selected, known_reg_codes)
          return ret unless ret == :next
        end

        update_addons(known_reg_codes)
        :next
      end

      # find the addon in the current config
      # @param addon [Hash] addon to find
      # @return [Hash, nil] found addon or nil
      def find_addon(addon)
        config.addons.find do |a|
          a["name"] == addon["name"] &&  a["version"] == addon["version"] &&
            a["arch"] == addon["arch"] && a["release_type"] == addon["release_type"]
        end
      end

      # update the reg. codes config
      def update_addons(known_reg_codes)
        ::Registration::Addon.selected.each do |addon|
          # FIXME: use a separate class for handling Autoyast addons,
          # define == operator, etc...
          new_addon = addon.to_h
          new_addon["reg_code"] = known_reg_codes[addon.identifier] || ""

          # already known?
          config_addon = find_addon(new_addon)

          # add or edit
          if config_addon
            config_addon.merge!(new_addon)
          else
            config.addons << new_addon
          end
        end
      end

      # run the main AutoYaST configuration dialog
      # @return [Symbol] the user input
      def configure_registration
        AutoyastConfigDialog.run(config)
      end
    end
  end
end
