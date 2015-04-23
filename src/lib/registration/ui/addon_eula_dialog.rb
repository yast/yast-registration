
require "yast"
require "registration/eula_downloader"
require "registration/eula_reader"
require "registration/helpers"

module Registration
  module UI
    # class for displaying and handling the add-on EULA dialog
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

      # display and run the dialog for accepting the extensions EULAs
      # @param selected_addons [Array<Addon>]
      def self.run(selected_addons)
        dialog = AddonEulaDialog.new(selected_addons)
        dialog.run
      end

      # constructor
      # @param selected_addons [Array<Addon>]
      def initialize(selected_addons)
        textdomain "registration"
        @addons = selected_addons
      end

      # display the EULA for each extension and wait for a button click
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
          next unless addon.eula_url && !addon.eula_url.empty?

          log.info "Addon '#{addon.name}' has an EULA at #{addon.eula_url}"
          eula_ret = accept_eula(addon)

          # any declined license needs to be handled separately
          break if eula_ret != :accepted
        end

        # go back or abort if any EULA has not been accepted, let the user
        # deselect the not accepted extension
        eula_ret == :accepted ? :next : eula_ret
      end

      private

      # download the addon EULAs to a temp dir
      # @param [Addon] addon the addon
      # @param [String] tmpdir target where to download the files
      def download_eula(addon, tmpdir)
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
      rescue StandardError => e
        log.error "Download failed: #{e.message}: #{e.backtrace}"
        # %s is an extension name, e.g. "SUSE Linux Enterprise Software Development Kit"
        Yast::Report.Error(_("Downloading the license for\n%s\nfailed.") % addon.label)
        return false
      end

      # prepare data for displaying the EULA dialog
      # @param [Addon] addon the addon
      # @param [EulaReader] eula_reader read eulas
      # @param [String] tmpdir target with the downloaded files
      def setup_eula_dialog(addon, eula_reader, tmpdir)
        id = "#{addon.label} extension EULA"
        Yast::ProductLicense.SetAcceptanceNeeded(id, true)
        Yast::ProductLicense.license_file_print = addon.eula_url

        # %s is an extension name, e.g. "SUSE Linux Enterprise Software Development Kit"
        title = _("%s License Agreement") % addon.label
        enable_back = true
        Yast::ProductLicense.DisplayLicenseDialogWithTitle(eula_reader.languages, enable_back,
          eula_reader.current_language, arg_ref(eula_reader.licenses), id, title)

        # display info file if present
        display_optional_info(File.join(tmpdir, "info.txt"))

        # display beta warning if present
        display_optional_info(File.join(tmpdir, "README.BETA"))
      end

      # run the EULA agreement dialog
      # @param [EulaReader] eula_reader read EULAs
      # @return [Symbol] :accepted, :back, :abort, :halt - user input
      def run_eula_dialog(eula_reader)
        base_product = false
        cancel_action = "abort"
        ret = Yast::ProductLicense.HandleLicenseDialogRet(arg_ref(eula_reader.licenses),
          base_product, cancel_action)
        log.debug "EULA dialog result: #{ret}"
        ret
      end

      # ask user to accept an addon EULA
      # @param [Addon] addon the addon
      # @return [Symbol] :accepted, :back, :abort, :halt
      def accept_eula(addon)
        Dir.mktmpdir("extension-eula-") do |tmpdir|
          return false unless download_eula(addon, tmpdir)
          eula_reader = EulaReader.new(tmpdir)

          setup_eula_dialog(addon, eula_reader, tmpdir)
          run_eula_dialog(eula_reader)
        end
      ensure
        Yast::ProductLicense.CleanUp()
      end

      # read a file if it exists and display it in a popup
      # @param info_file [String] the message is read from this file
      def display_optional_info(info_file)
        Yast::InstShowInfo.show_info_txt(info_file) if File.exist?(info_file)
      end
    end
  end
end
