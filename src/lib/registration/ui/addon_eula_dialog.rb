
require "yast"
require "registration/eula_downloader"
require "registration/helpers"

# TODO FIXME: this is used in a workaround, remove before RC/GM!!
require "tempfile"

module Registration
  module UI

    class AddonEulaDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include Yast

      attr_reader :addons

      Yast.import "Popup"
      Yast.import "ProductLicense"
      Yast.import "Report"
      Yast.import "Wizard"
      Yast.import "InstShowInfo"

      # create a new dialog for accepting importing a SSL certificate and run it
      def self.run(selected_addons)
        dialog = AddonEulaDialog.new(selected_addons)
        dialog.run
      end

      # @param selected_addons
      def initialize(selected_addons)
        textdomain "registration"
        @addons = selected_addons
      end

      # display the EULA for each dialog and wait for a button click
      # @return [Symbol] user input (:import, :cancel)
      def run
        Yast::Wizard.SetContents(
          # dialog title
          _("License Agreement"),
          Label(_("Downloading Licenses...")),
          "",
          false,
          false
        )

        all_accepted = addons.all? do |addon|
          if addon.eula_url && !addon.eula_url.empty?
            log.info "Addon '#{addon.name}' has an EULA at #{addon.eula_url}"
            accept_eula(addon)
          else
            # no EULA specified => accepted
            true
          end
        end

        # go back if any EULA has not been accepted, let the user deselect the
        # not accepted extension
        all_accepted ? :next : :back
      end

      private

      # ask user to accept an addon EULA
      # @param addon [SUSE::Connect::Product] the addon
      # @return [Boolean] true if the EULA has been accepted
      def accept_eula(addon)
        Dir.mktmpdir("extension-eula-") do |tmpdir|
          begin
            Yast::Popup.Feedback(
              _("Downloading License Agreement..."),
              addon.label
            ) do
              # download the license (with translations)
              loader = EulaDownloader.new(addon.eula_url, tmpdir,
                insecure: Helpers.insecure_registration)

              loader.download
            end
          rescue Exception => e
            log.error "Download failed: #{e.message}: #{e.backtrace}"
            # %s is an extension name, e.g. "SUSE Linux Enterprise Software Development Kit"
            Yast::Report.Error(_("Downloading the license for\n%s\nfailed.") % addon.label)
            return false
          end

          id = "#{addon.label} extension EULA"
          Yast::ProductLicense.SetAcceptanceNeeded(id, true)
          Yast::ProductLicense.license_file_print = addon.eula_url

          # %s is an extension name, e.g. "SUSE Linux Enterprise Software Development Kit"
          title = _("%s License Agreement") % addon.label
          eulas = read_downloaded_eulas(tmpdir)
          enable_back = true

          Yast::ProductLicense.DisplayLicenseDialogWithTitle(eulas.keys, enable_back,
            eula_lang(eulas.keys), arg_ref(eulas), id, title)

          # display info file if present
          display_optional_info(File.join(tmpdir, "info.txt"))

          # display beta warning if present
          display_optional_info(File.join(tmpdir, "README.BETA"))

          base_product = false
          action = "abort"
          ret = Yast::ProductLicense.HandleLicenseDialogRet(arg_ref(eulas), base_product, action)
          log.debug "EULA dialog result: #{ret}"
          Yast::ProductLicense.CleanUp()

          accepted = ret == :accepted
          log.info "EULA accepted: #{accepted}"
          accepted
        end
      end

      # get the EULA translation to display
      def eula_lang(eula_langs)
        current_language = Helpers.language || "en_US"
        current_language.tr!("-", "_")

        # exact match
        if eula_langs.include?(current_language)
          return current_language
        end

        # partial match or English fallback
        eula_langs.find { |eula_lang| remove_country_suffix(eula_lang) == current_language } || "en_US"
      end

      # read downloaded EULAs
      # @param dir [String] directly with EULA files
      # @return [Hash<String,String>] mapping { <locale> => <file_name> }
      def read_downloaded_eulas(dir)
        eulas = {}

        Dir["#{dir}/license.*"].each do |license|
          file = File.basename(license)

          case file
          when "license.txt"
            eulas["en_US"] = license
          when /\Alicense\.(.*)\.txt\z/
            eulas[$1] = license
          else
            log.warn "Ignoring unknown file: #{file}"
          end
        end

        log.info "EULA files in #{dir}: #{eulas}"
        eulas
      end

      # helper for removing the country suffix, e.g. "de_DE" => "de"
      # @param code [String] input locale name
      # @return [String] result locale name
      def remove_country_suffix(code)
        code.sub(/_.*\z/, "")
      end

      # read a file if it exists and display it in a popup
      # @param info_file [String] the message is read from this file
      def display_optional_info(info_file)
        Yast::InstShowInfo.show_info_txt(info_file) if File.exist?(info_file)
      end

    end
  end
end

