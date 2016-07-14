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
require "yaml"

require "yast"

module Registration
  Yast.import "Pkg"

  # storage for changed repositories
  class RepoStateStorage
    include Yast::Logger
    include Singleton

    # array of RepoState objects
    attr_accessor :repositories

    # location of the persistent storage (to store the data when restarting YaST)
    REPO_STATE_FILE = "/var/lib/YaST2/migration_repo_state.yml".freeze

    def initialize
      @repositories = []
    end

    # @param [String] repo_id repository ID
    # @param [Boolean] enabled the repository state to set
    #   (true = enable the repository, false = disable)
    def add(repo_id, enabled)
      repositories << RepoState.new(repo_id, enabled)
    end

    # restore all saved states
    def restore_all
      return if repositories.empty?

      # activate the original repository states
      repositories.each(&:restore)

      # save all repositories
      Yast::Pkg.SourceSaveAll
    end

    # write the current state to the persistent storage (to survive YaST restart)
    def write
      data = {}

      # repo_id => alias mapping
      repo_mapping = repository_mapping

      repositories.each do |repository|
        data[repo_mapping[repository.repo_id]] = repository.enabled
      end

      log.info "Exporting repository state: #{data.inspect}"
      File.write(REPO_STATE_FILE, data.to_yaml)
    end

    # read the stored state from the persistent storage
    def read
      # reset the previous list
      self.repositories = []

      return unless File.exist?(REPO_STATE_FILE)

      # inverse alias => repo_id mapping
      repo_mapping = repository_mapping.invert

      data = YAML.load_file(REPO_STATE_FILE)
      log.info "Importing repository state: #{data}"

      data.each do |repo_alias, enabled|
        if repo_mapping[repo_alias]
          add(repo_mapping[repo_alias], enabled)
        else
          log.warn "Repository #{repo_alias.inspect} is missing"
        end
      end
    end

    # clean the persistent storage
    def clean
      File.unlink(REPO_STATE_FILE) if File.exist?(REPO_STATE_FILE)
    end

  private

    # create repository mapping repo_id => alias
    # @return [Hash<Fixnum>,String>] the current repository mapping
    def repository_mapping
      ret = {}

      Yast::Pkg.SourceGetCurrent(false).each do |repo|
        ret[repo] = Yast::Pkg.SourceGeneralData(repo)["alias"]
      end

      log.info "Current repository setup: #{ret.inspect}"

      ret
    end
  end

  # store repository ID and it's original state (enabled/disabled)
  class RepoState
    include Yast::Logger

    attr_reader :repo_id, :enabled

    # create repository state status
    # @param [Fixnum] repo_id repository ID
    # @param [Boolean] enabled the repository state to set
    #   (true = enable the repository, false = disable)
    def initialize(repo_id, enabled)
      @repo_id = repo_id
      @enabled = enabled
    end

    # set the saved repository state
    def restore
      log.info "Restoring the original repository state: id: #{repo_id}, enabled: #{enabled}"
      Yast::Pkg.SourceSetEnabled(repo_id, enabled)
    end
  end
end
