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

# HTML escaping
require "cgi/util"

module Yast
  class SccClient < Client
    include Yast::Logger

    Yast.import "CommandLine"
    Yast.import "Pkg"
    Yast.import "Report"
    Yast.import "Wizard"

    def main
      textdomain "registration"

      if WFM.Args.include?("help")
        print_help
      else
        Wizard.CreateDialog

        begin
          ::Registration::SwMgmt.init

          return WFM.call("inst_scc", WFM.Args)
        rescue Registration::SourceRestoreError => e
          retry if fix_repositories(e.message)
        rescue Registration::PkgAborted => e
          log.info "User abort..."
        ensure
          Wizard.CloseDialog
        end
      end
    end

  private

    # Print help in command line mode
    def print_help
      cmdline_description = {
        "id"   => "scc",
        # Command line help text for the repository module, %1 is "SUSEconnect"
        "help" => _("Use '%s' instead of this YaST module.") % "SUSEconnect"
      }

      CommandLine.Run(cmdline_description)
    end

    # Let the user manually fix the broken repositories
    # @return [Boolean] true if the repository manager was successfuly closed,
    #   false after pressing [Cancel]
    def fix_repositories(details)
      # TRANSLATORS: Error message in RichText format, %s contains the details from libzypp
      Report.LongError(_("<p>The repository initialization failed. " \
        "Disable (or remove) the offending service or repository " \
        "in the repository manager.</p><p>Details:</p><p>%s</p>") % CGI.escapeHTML(details))

      ret = WFM.call("repositories", WFM.Args)
      log.info "repository manager result: #{ret}"

      # drop all loaded repos, force complete reloading
      Pkg.SourceFinishAll
      ret == :next
    end
  end unless defined?(SccClient)
end

Yast::SccClient.new.main
