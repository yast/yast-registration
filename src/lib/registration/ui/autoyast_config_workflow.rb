
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

    class AutoyastConfigWorkflow
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Pkg"
      Yast.import "Report"
      Yast.import "Sequencer"

      # create a new dialog for accepting and importing a SSL certificate and run it
      def self.run(config)
        workflow = AutoyastConfigWorkflow.new(config)
        workflow.run
      end

      def initialize(config)
        textdomain "registration"

        @config = config
      end

      def run
        aliases = {
          "general"         => lambda { configure_registration() },
          "addons"          => [ lambda { select_addons() }, true ],
          "remote_addons"   => [ lambda { select_remote_addons() }, true ],
          "addons_eula"     => [ lambda { addons_eula() }, true ],
          "addons_regcodes" => [ lambda { addons_reg_codes() }, true ]
        }

        sequence = {
          "ws_start" => "general",
          "general"  => {
            :abort   => :abort,
            :next    => :next,
            :addons  => "addons"
          },
          "addons" => {
            :abort   => :abort,
            :next    => "general",
            :download => "remote_addons"
          },
          "remote_addons" => {
            :addons  => "addons",
            :abort   => :abort,
            :next    => "addons_eula"
          },
          "addons_eula" => {
            :abort   => :abort,
            :next    => "addons_regcodes"
          },
          "addons_regcodes" => {
            :abort   => :abort,
            :next    => "addons"
          }
        }

        log.info "Starting scc_auto sequence"
        Yast::Sequencer.Run(aliases, sequence)
      end

      private

      attr_reader :config

      def select_addons
        AutoyastAddonDialog.run(config.addons)
      end

      def select_remote_addons
        if !::Registration::SwMgmt.init
          Report.Error(Pkg.LastError)
          return :abort
        end

        url = ::Registration::UrlHelpers.registration_url
        registration = ::Registration::Registration.new(url)

        ret = nil

        success = ::Registration::ConnectHelpers.catch_registration_errors do
          ret = AddonSelectionDialog.run(registration)
        end

        success ? ret : :addons
      end

      def addons_eula
        AddonEulaDialog.run(::Registration::Addon.selected)
      end

      def collect_known_reg_codes
        Hash[config.addons.map{|a| [a["name"], a["reg_code"]]}]
      end

      def addons_reg_codes
        return :next if ::Registration::Addon.selected.all?(&:free)

        known_reg_codes = collect_known_reg_codes
        ret = AddonRegCodesDialog.run(::Registration::Addon.selected, known_reg_codes)
        return ret unless ret == :next

        update_addons(known_reg_codes)
        :next
      end

      def find_addon(addon)
        config.addons.find do |a|
          a["name"] == addon["name"] &&  a["version"] == addon["version"] &&
            a["arch"] == addon["arch"] && a["release_type"] == addon["release_type"]
        end
      end

      def update_addons(known_reg_codes)
        ::Registration::Addon.selected.each do |addon|
          new_addon = {
            "name" => addon.identifier,
            "version" => addon.version,
            "arch" => addon.arch,
            "release_type" => addon.release_type,
            "reg_code" => known_reg_codes[addon.identifier] || ""
          }

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

      def configure_registration
        AutoyastConfigDialog.run(config)
      end

    end
  end
end

