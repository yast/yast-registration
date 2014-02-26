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
        log.info(
          "Searching for SLP registration services of type #{SUPPORTED_SERVICES.join(', ')}"
        )
        SUPPORTED_SERVICES.each do |service_name|
          services.concat(SlpService.all(service_name))
        end
      end

      if services.empty?
        return Report.Message _('No registration server found')
      else
        log.info(
          "Found #{services.size} services: #{services.map(&:slp_url).join(', ')}"
        )
      end

      select_registration_service
    end

    private

    def select_registration_service
      UI.OpenDialog(
        Opt(:decorated),
        VBox(
          Label(_('Available local registration servers')),
          VSpacing(0.6),
          RadioButtonGroup(
            Id(:services),
            Left(
              HVSquash(
                VBox(*services_radio_buttons)
              )
            )
          ),
          ButtonBox(
            PushButton(Id(:ok), Label.OKButton),
            PushButton(Id(:cancel), Label.CancelButton)
          )
        )
      )

      loop do
        dialog_result = UI.UserInput
        case dialog_result
        when :ok
          selected = UI.QueryWidget(Id(:services), :CurrentButton)
          if !selected
            Report.Error(_('Please select one of the registration servers'))
            next
          end
          select_service(services[selected.to_i])
          UI.CloseDialog
          break
        when :cancel
          UI.CloseDialog
          break
        end
      end
    end

    def select_service(service)
      log.info("Selected registration service: #{service.inspect}")
      #TODO Assign the service to a module or a global object now
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

    def service_description(service)
      name = REGISTRATION_SERVICES[service.name]
      url  = "#{service.protocol}://#{service.host}:#{service.port} "
      attributes = service.attributes.to_h.map do |name, value|
        "#{name}=#{value} "
      end
      "#{name}  #{url}  #{attributes.join}"
    end

    def busy_box
      Popup.ShowFeedback(_('Searching for registration servers...'), '')
      yield
    ensure
      Popup.ClearFeedback
    end
  end unless defined?(DiscoverRegistrationServicesClient)
  DiscoverRegistrationServicesClient.new.main
end
