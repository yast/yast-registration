
require "yast/suse_connect"

require "registration/helpers"
require "registration/url_helpers"
require "registration/ui/service_selection_dialog"

module Yast
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
      service = ::Registration::UI::ServiceSelectionDialog.run(services)
      return nil unless service.respond_to?(:slp_url)
      url = ::Registration::UrlHelpers.service_url(service.slp_url)
      log.info "Selected service URL: #{url}"
      url
    end
  end unless defined?(DiscoverRegistrationServicesClient)
  DiscoverRegistrationServicesClient.new.main
end
