
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
            log.info "Addon '#{addon.short_name}' has an EULA at #{addon.eula_url}"
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
              addon.short_name
            ) do
              # download the license (with translations)
              loader = EulaDownloader.new(addon.eula_url, tmpdir,
                insecure: Helpers.insecure_registration)

              loader.download
            end
          rescue Exception => e
            log.error "Download failed: #{e.message}: #{e.backtrace}"
            # %s is an extension name, e.g. "SUSE Linux Enterprise Software Development Kit"
            Yast::Report.Error(_("Downloading the license for\n%s\nfailed.") % addon.short_name)
            #FIXME change for GA!!!
            return true
          end

          id = "#{addon.short_name} extension EULA"
          Yast::ProductLicense.SetAcceptanceNeeded(id, true)
          Yast::ProductLicense.license_file_print = addon.eula_url

          # %s is an extension name, e.g. "SUSE Linux Enterprise Software Development Kit"
          title = _("%s License Agreement") % addon.short_name
          eulas = read_downloaded_eulas(tmpdir)
          enable_back = true

          Yast::ProductLicense.DisplayLicenseDialogWithTitle(eulas.keys, enable_back,
            eula_lang(eulas.keys), arg_ref(eulas), id, title)

          # TODO FIXME: this a workaround, remove before RC/GM!!
          display_beta_warning(addon.short_name)

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

      # TODO FIXME: this a workaround, remove before RC/GM!!
      def display_beta_warning(addon_name)
        beta_warning = <<EOF

   #{addon_name}

   Attention! You are accessing our Beta Distribution.  If you install
   any package, note that we can NOT GIVE ANY SUPPORT for your system -
   no matter if you update from a previous system or do a complete
   new installation.

   Use this BETA distribution at your own risk! We recommend it for
   testing, porting and evaluation purposes but not for any critical
   production systems.

   Use this distribution at your own risk - and remember to have a
   lot of fun! :)

                Your SUSE Linux Enterprise Team
EOF

        # InstShowInfo reads the text from a file so use a tempfile
        file = Tempfile.new("beta-warning-")
        begin
          file.write(beta_warning)
          file.close
          Yast::InstShowInfo.show_info_txt(file.path)
        ensure
          file.unlink
        end
      end

    end
  end
end

