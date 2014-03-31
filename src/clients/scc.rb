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

# this is just a wrapper for running the SCC client in installed system

require "yast"
require "registration/sw_mgmt"

module Yast
  class SccClient < Client
    Yast.import "Wizard"
    Yast.import "CommandLine"

    def main

      textdomain "registration"

      if WFM.Args.include?("help")
        cmdline_description = {
          "id" => "scc",
          # Command line help text for the repository module, %1 is "SUSEconnect"
          "help" => _("Use '%s' instead of this YaST module.") % "SUSEconnect",
        }

        CommandLine.Run(cmdline_description)
      else
        Wizard.CreateDialog
        ::Registration::SwMgmt.init

        WFM.call("inst_scc")

        Wizard.CloseDialog
      end
    end
  end
end

Yast::SccClient.new.main
