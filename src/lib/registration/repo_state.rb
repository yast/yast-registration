# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2014 Novell, Inc. All Rights Reserved.
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

require "singleton"

require "yast"

module Registration
  Yast.import "Pkg"

  # storage for changed repositories
  class RepoStateStorage
    include Singleton

    # array of RepoState objects
    attr_accessor :repositories

    def initialize
      @repositories = []
    end
  end

  # store repository ID and it's original state (enabled/disabled)
  class RepoState
    include Yast::Logger

    attr_reader :repo_id, :enabled

    def initialize(repo_id, enabled)
      @repo_id = repo_id
      @enabled = enabled
    end

    def restore
      log.info "Restoring the original repository state: id: #{repo_id}, enabled: #{enabled}"
      Yast::Pkg.SourceSetEnabled(repo_id, enabled)
    end
  end
end
