module Yast
  import 'SlpService'
  import 'UI'
  import 'Label'
  import 'Report'

  class DiscoverRegistrationServicesClient < Client
    include Yast::Logger

    REGISTRATION_SERVICES = {
      'susemanager' => 'SUSE Manager'
    }

    SUPPORTED_SERVICES = REGISTRATION_SERVICES.keys

    attr_reader :services

    def initialize
      @services = []
    end

    def main
      textdomain "registration"

      busy_box do
        log.info "Searching for #{SUPPORTED_SERVICES.inspect} SLP services"
        SUPPORTED_SERVICES.each do |service_name|
          services.concat(SlpService.all(service_name))
        end
      end

      log.debug "Found services: #{services.inspect}"
      log.info "Found #{services.size} services: #{services.map(&:slp_url).inspect}"

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
            Label(_("Select a server from the list or press Cancel\n" +
                "to use the default SUSE registration server.")),
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
              PushButton(Id(:ok), Label.OKButton),
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

            selected_service = services[selected.to_i]
            log.info "Selected service #{selected_service.inspect}"

            url = service_url(selected_service.slp_url)
            log.info "Selected service URL: #{url}"

            return url
          when :cancel
            break
          end
        end
      ensure
        UI.CloseDialog
      end
    end

    # convert service URL to plain URL, remove the SLP service prefix
    # "service:susemanager:https://scc.suse.com/connect" ->
    # "https://scc.suse.com/connect"
    def service_url(service)
      service.sub(/\Aservice:[^:]+:/, "")
    end

    def services_radio_buttons
      services.map.with_index do |service, index|
        Left(
          RadioButton(
            Id(index.to_s),
            service_description(service),
            false
          )
        )
      end
    end

    # Create radio button label for a SLP service
    # @param service [Yast::SlpServiceClass::Service] SLP service
    # @return [String] label
    def service_description(service)
      url  = service_url(service.slp_url)
      descr = service.attributes.to_h[:description]

      # display URL and the description if it is present
      (descr && !descr.empty?) ? "#{descr} (#{url})" : url
    end

    def busy_box
      Popup.ShowFeedback(_("Searching..."), _("Looking up local registration servers..."))
      yield
    ensure
      Popup.ClearFeedback
    end
  end unless defined?(DiscoverRegistrationServicesClient)
  DiscoverRegistrationServicesClient.new.main
end
