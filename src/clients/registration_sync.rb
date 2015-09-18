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
require "registration/ui/registration_sync_workflow"

module Yast
  class RegistrationSyncClient < Client
    Yast.import "Wizard"

    def main
      textdomain "registration"

      # create the Wizard dialog if needed
      wizard_present = Wizard.IsWizardDialog
      Wizard.CreateDialog unless wizard_present

      begin
        ::Registration::UI::RegistrationSyncWorkflow.run
      ensure
        Wizard.CloseDialog unless wizard_present
      end
    end
  end unless defined?(YaST::RegistrationSyncClient)
end

Yast::RegistrationSyncClient.new.main
