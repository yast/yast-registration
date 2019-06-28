# typed: true

require "yast/suse_connect"

require "registration/helpers"
require "registration/url_helpers"
require "registration/ui/regservice_selection_dialog"

module Yast
  class DiscoverRegistrationServicesClient < Client
    include Yast::Logger

    # @return [Array<SlpServiceClass::Service>] list of candidate services
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
      service = ::Registration::UI::RegserviceSelectionDialog.run(services: services)
      case service
      when :scc
        nil
      when :cancel
        :cancel
      else
        url = ::Registration::UrlHelpers.service_url(service.slp_url)
        log.info "Selected service URL: #{url}"
        url
      end
    end
  end unless defined?(DiscoverRegistrationServicesClient)
  DiscoverRegistrationServicesClient.new.main
end
