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

module Registration
  module UI
    class ServiceSelectionDialog < ::UI::Dialog
      # @return [Array<SlpServiceClass::Service] list of services to show
      attr_reader :services

      # Run dialog
      #
      # @param services [Array<SlpServiceClass::Service] list of services to show
      # @return [SlpServiceClass::Service,Symbol] selected service or symbol (:scc or :cancel)
      #
      # @see #run
      def self.run(services)
        new(services).run
      end

      # Constructor
      #
      # @param services [Array<SlpServiceClass::Service] list of services to show
      def initialize(services = [])
        super()

        Yast.import "UI"
        Yast.import "Label"
        Yast.import "Report"

        textdomain "registration"

        @services = services
      end

      # Handler for the Ok button
      #
      # If no option was selected, a error message is shown.
      def ok_handler
        selected = Yast::UI.QueryWidget(Id(:services), :CurrentButton)
        if !selected
          Yast::Report.Error(_("No registration server selected."))
        else
          value = selected == "scc" ? :scc : services[selected.to_i]
          finish_dialog(value)
        end
      end

      # Handler for the cancel button
      def cancel_handler
        finish_dialog(:cancel)
      end

    protected

      # Dialog's initial content
      #
      # @return [Yast::Term] Content
      def dialog_content
        MarginBox(2, 0.5,
          VBox(
            # popup heading (in bold)
            Heading(_("Local Registration Servers")),
            VSpacing(0.5),
            Label(_("Select a detected registration server from the list\n" \
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
            button_box
          ))
      end

      # Dialog options
      #
      # @return [Yast::Term] Dialog's options
      def dialog_options
        Yast::Term.new(:opt, :decorated)
      end

      # Return dialog's buttons
      #
      # @return [Yast::Term] Buttons' description
      def button_box
        ButtonBox(
          PushButton(Id(:ok), Opt(:default), Yast::Label.OKButton),
          PushButton(Id(:cancel), Yast::Label.CancelButton)
        )
      end

      # Return service radio buttons
      #
      # Creates one radio button for each service and add a special
      # one for SCC.
      #
      # @return [Yast::Term] Service radio button's description
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
          _("SUSE Customer Center (%s)") % SUSE::Connect::YaST::DEFAULT_URL,
          true)))
      end
    end
  end
end
