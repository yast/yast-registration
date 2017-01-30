# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2013 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------
#
#

require "yast"

require "registration/registration"

module Yast
  class ExtensionClient < Client
    include Yast::Logger

    Yast.import "Wizard"

    def main
      # Extension and module selection dialog's run method expects a dialog to exist already
      Wizard.CreateDialog

      begin
        ::Registration::SwMgmt.init
        return WFM.call("inst_scc", WFM.Args + ["select_extensions"])
      ensure
        Wizard.CloseDialog
      end
    end
  end unless defined?(ExtensionClient)
end

Yast::ExtensionClient.new.main
