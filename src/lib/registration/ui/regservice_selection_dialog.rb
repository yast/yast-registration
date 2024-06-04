# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# ------------------------------------------------------------------------------

require "yast"
require "ui/dialog"
require "registration/helpers"
require "slp/dialogs/service_selection"

module Registration
  module UI
    # This class implements a SCC/RMT service selection dialog.
    class RegserviceSelectionDialog < Yast::Dialogs::ServiceSelection
      Yast.import "UI"
      Yast.import "Label"
      Yast.import "Report"

      # Run dialog
      #
      # The return value will be:
      # * A service in case one RMT server was selected
      # * :scc symbol if default SCC was selected
      # * :cancel symbol if the SCC was canceled (pressing the 'cancel' button)
      #
      # @example Select the default SCC service
      #   Registration::UI::SelectionServiceDialog.run(services) #=> :scc
      #
      # @example Select some RMT service
      #   Registration::UI::SelectionServiceDialog.run(services)
      #     #=> #<Yast::SlpServiceClass::Service...>
      #
      # @param services    [Array<SlpServiceClass::Service] List of services to show.
      # @param heading     [String] Text to be shown as dialog heading. A default text
      #                             will be used if it's not specified.
      # @param description [String] Text to be shown as description. A default text
      #                             will be used if it's not specified.
      # @return [SlpServiceClass::Service,Symbol] selected service or symbol (:scc or :cancel).
      #
      # @see #run
      def self.run(services:, heading: nil, description: nil)
        new(services: services, heading: heading, description: description).run
      end

      # Constructor
      #
      # @param services    [Array<SlpServiceClass::Service] List of services to show.
      # @param heading     [String] Text to be shown as dialog heading. A default text
      #                             will be used if it's not specified.
      # @param description [String] Text to be shown as description. A default text
      #                             will be used if it's not specified.
      def initialize(services: [], heading: nil, description: nil)
        textdomain "registration"
        description_default = _("Select a detected registration server " \
          "from the list\nor the default SUSE registration server.")
        super(
          services:        [scc_service] + services,
          heading:         heading || _("Local Registration Servers"),
          description:     description || description_default,
          no_selected_msg: _("No registration server selected")
        )
      end

      # Handler for the Ok button
      #
      # If no option was selected, a error message is shown.
      #
      # @see Yast::Dialogs::ServiceSelection#ok_handler
      def ok_handler
        selected = super
        finish_dialog(:scc) if selected == scc_service
      end

      # Return the service description to be shown to the user
      #
      # This method just overrides the services description in case
      # of a String is passed (instead of a SlpServiceClass::Service).
      # It's needed because the "scc" option is not a proper service, just a
      # special value.
      #
      # @param  service [SlpServiceClass::Service,String] Service to describe
      # @return [String] Service description
      #
      # @see Yast::Dialogs::ServiceSelection#service_to_description
      def service_to_description(service)
        service.is_a?(String) ? service : super
      end

    private

      # Default registration server
      #
      # return [String] Returns a string representing the default SCC service.
      def scc_service
        @scc_service ||= _("SUSE Customer Center (%s)") % SUSE::Connect::YaST::DEFAULT_URL
      end
    end
  end
end
