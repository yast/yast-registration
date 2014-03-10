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
# client for setting the original repository states
#

require "yast"

require "registration/repo_state"

module Yast
  class SccFinishClient < Client
    include Yast::Logger

    def main
      Yast.import "Pkg"

      textdomain "registration"

      if WFM.Args.empty?
        raise "#{File.basename(__FILE__)}: missing parameter"
      else
        func = WFM.Args(0)
      end

      log.info "starting #{__FILE__} (func: #{func})"

      if func == "Info"
        return {
          "steps" => 1,
          # progress step title
          "title" => _("Setting original repository configuration..."),
          "when"  => ::Registration::RepoStateStorage.instance.repositories.empty? ?
            [] : [:installation, :live_installation, :update, :autoinst]
        }
      elsif func == "Write"
        # nothing to write
        changed_repos = ::Registration::RepoStateStorage.instance.repositories
        return nil if changed_repos.empty?

        # activate the original repository states
        changed_repos.each(&:restore_state)

        # save all repositories
        Pkg.SourceSaveAll
      else
        raise "#{File.basename(__FILE__)}:unknown parameter: #{func.inspect}"
      end

      log.info "#{__FILE__} finished"
    end

  end
end

Yast::SccFinishClient.new.main
