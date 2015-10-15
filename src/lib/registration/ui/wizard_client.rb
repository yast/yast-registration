# ------------------------------------------------------------------------------
# Copyright (c) 2015 SUSE LLC
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
#

require "yast"

module Registration
  module UI
    # The base class for several clients using the Wizard module
    # with exception handling.
    class WizardClient
      include Yast::I18n
      include Yast::Logger

      Yast.import "Wizard"
      Yast.import "Report"

      def initialize
        textdomain "registration"
      end

      # Run the main workflow, opens a Wizard dialog if not present
      # and handles raised exceptions
      # @return [Symbol] resulting workflow symbol (:next, :abort, ...)
      def main
        # create the Wizard dialog if needed
        wizard_present = Yast::Wizard.IsWizardDialog
        Yast::Wizard.CreateDialog unless wizard_present

        begin
          run
        ensure
          Yast::Wizard.CloseDialog unless wizard_present
        end
      end

      # Run the main workflow, handles exceptions raised during the client call.
      # @return [Symbol] resulting workflow symbol (:next, :abort, ...), :abort
      #   is returned when an exception is raised.
      def run
        ret = run_sequence
        log.info "Sequence result: #{ret}"
        ret
      rescue => e
        log.error "Caught error: #{e.class}: #{e.message.inspect}, #{e.backtrace}"
        # TRANSLATORS: error message, %s are details
        Yast::Report.Error(_("Internal error: %s") % e.message)
        return :abort
      end

      # This is main workflow sequence, it needs to be redefined in the derived class.
      # @return [Symbol] resulting workflow symbol (:next, :abort, ...)
      def run_sequence
        raise NotImplementedError, "method run_sequence() must be defined in the derived class"
      end
    end
  end
end
