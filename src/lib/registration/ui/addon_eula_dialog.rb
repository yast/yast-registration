
require "yast"
require "registration/eula_downloader"

module Registration
  module UI

    class AddonEulaDialog
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts

      attr_accessor :addons

      Yast.import "Popup"
      Yast.import "ProductLicense"
      Yast.import "Report"
      Yast.import "Wizard"

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

          Yast::ProductLicense.AskLicensesAgreementWithHeading(
            [tmpdir],
            Yast::ProductLicense.license_patterns,
            # do not continue if not accepted
            "abort",
            # enable [Back]
            true,
            # base product
            false,
            # require agreement
            true,
            # dialog title
            _("Extension and Module License Agreement"),
            # %s is an extension name, e.g. "SUSE Linux Enterprise Software Development Kit"
            _("%s License Agreement") % addon.short_name
          ) == :accepted
        end
      end

    end
  end
end

