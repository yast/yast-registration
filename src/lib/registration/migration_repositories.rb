
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
require "registration/sw_mgmt"

module Registration
  # this class activates the migration repositories
  class MigrationRepositories
    include Yast::Logger

    Yast.import "Pkg"

    def self.reset
      log.info "Resetting upgrade repos config"
      repos = Yast::Pkg.GetUpgradeRepos()
      repos.each { |repo| Yast::Pkg.RemoveUpgradeRepo(repo) }

      # deselect all pre-selected packages or patches
      Yast::Pkg.PkgReset
    end

    attr_accessor :repositories, :install_updates

    def initialize
      @repositories = []
      # install updates by default
      @install_updates = true
    end

    # use the repositories from a libzypp service for the migration
    # @param [String] service_name name of the service
    def add_service(service_name)
      service_repos = SwMgmt.service_repos(service_name)
      repositories.concat(service_repos)
    end

    # is any migration repo an update repo?
    # @return [Boolean] true if at least one migration repository is an update
    #   repository
    def has_update_repo?
      repositories.any? { |repo| repo["is_update_repo"] }
    end

    # activate the migration repositories to install the updates
    def activate
      set_solver

      repositories.each do |repo|
        if repo["is_update_repo"] && !install_updates
          log.info "Skipping update repository: #{repo["alias"]}"
        else
          log.info "Adding upgrade repo: #{repo["alias"]}"
          Yast::Pkg.AddUpgradeRepo(repo["SrcId"])
        end
      end

      Yast::Pkg.PkgSolve(false)

      select_patches if install_updates
    end

    private

    # set the solver flags for online migration
    # @see https://fate.suse.com/319138
    def set_solver
      log.info "Setting the solver flag for online migration"
      Yast::Pkg.SetSolverFlags("ignoreAlreadyRecommended" => true,
                               "allowVendorChange"        => false)
    end

    # preselect all applicable patches (except optional ones)
    def select_patches
      patches_count = Yast::Pkg.ResolvablePreselectPatches(:all)
      log.info "Preselected patches: #{patches_count}"
    end
  end
end
