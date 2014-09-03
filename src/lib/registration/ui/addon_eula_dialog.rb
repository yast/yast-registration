
require "yast"
require "registration/eula_downloader"
require "registration/helpers"

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
      # @return [Symbol] user input (:next, :back, :abort, :halt)
      def run
        Yast::Wizard.SetContents(
          # dialog title
          _("License Agreement"),
          Label(_("Downloading Licenses...")),
          "",
          false,
          false
        )

        # Default: no EULA specified => accepted
        eula_ret = :accepted

        addons.each do |addon|
          if addon.eula_url && !addon.eula_url.empty?
            log.info "Addon '#{addon.name}' has an EULA at #{addon.eula_url}"
            eula_ret = accept_eula(addon)
            # any declined license needs to be handled separately
            break if eula_ret != :accepted
          end
        end

        # go back or abort if any EULA has not been accepted, let the user
        # deselect the not accepted extension
        eula_ret == :accepted ? :next : eula_ret
      end

      private

      # download the addon EULAs to a temp dir
      # @param [SUSE::Connect::Product] addon the addon
      # @param [String] tmpdir target where to download the files
      def download_eula(addon, tmpdir)
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
          true
        rescue Exception => e
          log.error "Download failed: #{e.message}: #{e.backtrace}"
          # %s is an extension name, e.g. "SUSE Linux Enterprise Software Development Kit"
          Yast::Report.Error(_("Downloading the license for\n%s\nfailed.") % addon.label)
          return false
        end
      end

      # prepare data for displaying the EULA dialog
      # @param [SUSE::Connect::Product] addon the addon
      # @param [Hash<String,String>] eulas mapping { <locale> => <file_name> }
      # @param [String] tmpdir target whith the downloaded files
      def setup_eula_dialog(addon, eulas, tmpdir)
        id = "#{addon.label} extension EULA"
        Yast::ProductLicense.SetAcceptanceNeeded(id, true)
        Yast::ProductLicense.license_file_print = addon.eula_url

        # %s is an extension name, e.g. "SUSE Linux Enterprise Software Development Kit"
        title = _("%s License Agreement") % addon.label
        enable_back = true
        Yast::ProductLicense.DisplayLicenseDialogWithTitle(eulas.keys, enable_back,
          eula_lang(eulas.keys), arg_ref(eulas), id, title)

        # display info file if present
        display_optional_info(File.join(tmpdir, "info.txt"))

        # display beta warning if present
        display_optional_info(File.join(tmpdir, "README.BETA"))
      end

      # run the EULA agreement dialog
      # @param [Hash<String,String>] eulas mapping { <locale> => <file_name> }
      # @return [Symbol] :accepted, :back, :abort, :halt - user input
      def run_eula_dialog(eulas)
        base_product = false
        action = "abort"
        ret = Yast::ProductLicense.HandleLicenseDialogRet(arg_ref(eulas), base_product, action)
        log.debug "EULA dialog result: #{ret}"
        ret
      end

      # ask user to accept an addon EULA
      # @param [SUSE::Connect::Product] addon the addon
      # @return [Symbol] :accepted, :back, :abort, :halt
      def accept_eula(addon)
        Dir.mktmpdir("extension-eula-") do |tmpdir|
          return false unless download_eula(addon, tmpdir)
          eulas = read_downloaded_eulas(tmpdir)

          setup_eula_dialog(addon, eulas, tmpdir)
          run_eula_dialog(eulas)
        end
      ensure
        Yast::ProductLicense.CleanUp()
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

