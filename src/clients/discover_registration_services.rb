
require "registration/helpers"
require "registration/url_helpers"

module Yast
  import 'UI'
  import 'Label'
  import 'Report'

  class DiscoverRegistrationServicesClient < Client
    include Yast::Logger

    attr_reader :services

    def initialize
      @services = []
    end

    def main
      textdomain "registration"

      @services = ::Registration::UrlHelpers.slp_discovery_feedback

      services.empty? ? nil : select_registration_service
    end

    private

    def select_registration_service
      UI.OpenDialog(
        Opt(:decorated),
        MarginBox(2, 0.5,
          VBox(
            # popup heading (in bold)
            Heading(_('Local Registration Servers')),
            VSpacing(0.5),
            Label(_("Select a detected registration server from the list\n" +
                  "or the default SUSE registration server.")),
            VSpacing(0.5),
            RadioButtonGroup(
              Id(:services),
              Left(
                HVSquash(
                  VBox(*services_radio_buttons)
                )
              )
            ),
            VSpacing(Opt(:vstretch), 1),
            ButtonBox(
              PushButton(Id(:ok), Opt(:default), Label.OKButton),
              PushButton(Id(:cancel), Label.CancelButton)
            )
          )
        )
      )

      begin
        loop do
          dialog_result = UI.UserInput
          case dialog_result
          when :ok
            selected = UI.QueryWidget(Id(:services), :CurrentButton)
            if !selected
              # error popup
              Report.Error(_("No registration server selected."))
              next
            end

            break if selected == "scc"

            selected_service = services[selected.to_i]
            log.info "Selected service #{selected_service.inspect}"

            url = ::Registration::UrlHelpers.service_url(selected_service.slp_url)
            log.info "Selected service URL: #{url}"

            return url
          when :cancel
            return :cancel
          end
        end
      ensure
        UI.CloseDialog
      end
    end

    def services_radio_buttons
      widgets = services.map.with_index do |service, index|
        Left(
          RadioButton(
            Id(index.to_s),
            ::Registration::Helpers.service_description(service),
            false
          )
        )
      end

      widgets.unshift(Left(RadioButton(Id("scc"),
          # %s is the default SCC URL
          _("SUSE Customer Center (%s)") % SUSE::Connect::Client::DEFAULT_URL,
          true)))
    end

  end unless defined?(DiscoverRegistrationServicesClient)
  DiscoverRegistrationServicesClient.new.main
end
