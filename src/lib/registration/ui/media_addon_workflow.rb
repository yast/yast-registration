
require "yast"
# require "registration/helpers"
# require "registration/connect_helpers"
# require "registration/url_helpers"
#
# require "registration/ui/autoyast_addon_dialog"
# require "registration/ui/autoyast_config_dialog"
# require "registration/ui/addon_selection_dialog"
# require "registration/ui/addon_eula_dialog"
# require "registration/ui/addon_reg_codes_dialog"

module Registration
  module UI
    class MediaAddonWorkflow
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      Yast.import "Pkg"
      Yast.import "Report"
      Yast.import "Sequencer"

      # run workflow for registering a media add-on
      def self.run(repo_id)
        workflow = MediaAddonWorkflow.new(repo_id)
        workflow.run
      end

      def initialize(repo_id)
        textdomain "registration"

        @repo_id = repo_id
      end

      # The media add-on workflow is:
      #
      # - find the add-on product resolvable from repo_id
      # - register the base system if it is not registered yet
      # - get available addons from SCC
      # - find the matching add-on product from media
      # - ask for a reg code if needed
      # - register the add-on
      def run
        aliases = {
          "find_products"       => [->() { find_products }, true],
          "register_base"       => ->() { register_base },
          "load_remote_addons"  => ->() { load_remote_addons },
          "select_media_addons" => [->() { select_media_addons }, true],
          "register_addons"     => [->() { register_addons }, true]
        }

        sequence = {
          "ws_start"            => "find_products",
          "find_products"       => {
            abort:  :abort,
            finish: :finish,
            next:   "register_base"
          },
          "register_base"       => {
            abort: :abort,
            next:  "load_remote_addons"
          },
          "load_remote_addons"  => {
            abort: :abort,
            next:  "select_media_addons"
          },
          "select_media_addons" => {
            abort:  :abort,
            finish: :finish,
            next:   "register_addons"
          },
          # TODO: do we need to accept the EULA again?
          #          "addons_eula"     => {
          #            abort: :abort,
          #            next:  "addons_regcodes"
          #          },
          "register_addons"     => {
            abort: :abort,
            next:  :next
          }
        }

        log.info "Starting scc_auto sequence"
        Sequencer.Run(aliases, sequence)
      end

      private

      attr_accessor :addons, :repo_id, :products

      def find_products
        if !SwMgmt.init
          Report.Error(Pkg.LastError)
          return :abort
        end

        Pkg.SourceLoad

        # find the products from the media addo-on
        # TODO: only installed products??
        self.products = Pkg.ResolvableProperties("", :product, "").select do |product|
          product["source"] == @repo_id
        end

        log.info "Found: #{products.size} product(s): #{products.inspect}"

        if products.empty?
          repo_data = Pkg.SourceGeneralData(@repo_id)
          log.warn "Repository #{repo_data["name"]} (#{repo_data["alias"]}) " \
            "does not provide any product resolvable"
          log.warn "Skipping add-on registration"
          return :finish
        end

        :next
      end

      def register_base
        if !::Registration::Registration.is_registered?
          # TODO: register the base system if not already registered
        end

        :next
      end

      def register_addons
        :next
      end

      def load_remote_addons
        url = UrlHelpers.registration_url
        registration = ::Registration::Registration.new(url)
        registration_ui = ::Registration::RegistrationUI.new(registration)

        self.addons = registration_ui.get_available_addons

        return :cancel if addons == :cancel

        :next
      end

      def select_media_addons
        # select a remote addon for each product
        products.each do |product|
          remote_addon = addons.find do |addon|
            product["name"] == addon.name &&
              product["version"] == addon.version &&
              product["arch"] == addon.arch
          end

          if remote_addon
            remote_addon.selected
          else
            product_label = "#{product["display_name"]} (#{product["name"]}" \
              "-#{product["version"]}-#{product["arch"]})"

            # TRANSLATORS: %s is a product name
            Report.Error(_("Cannot find remote product %s.\n" \
                  "The product cannot be registered.") % product_label
            )
          end
        end

        # FIXME: remove this
        return :next if ENV["MEDIA_ADDON"]

        # no add-on => no registration
        Addon.selected.empty? ? :finish : :next
      end
    end
  end
end
