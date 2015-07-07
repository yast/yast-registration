
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
  # this class activates the migration services and repositories
  class MigrationRepositories
    include Yast::Logger

    Yast.import "Pkg"

    # reset the libzypp migration setup
    def self.reset
      # reset the solver
      Yast::Pkg.SetSolverFlags("reset" => true)

      # deselect all pre-selected packages or patches
      Yast::Pkg.PkgReset
    end

    attr_accessor :repositories, :services, :install_updates

    def initialize
      @repositories = []
      @services = []
      # install updates by default
      @install_updates = true
    end

    # does any configured service contain an update repo?
    # @return [Boolean] true if at least one service repository is an update
    #   repository
    def service_update_repo?
      services_repositories.any? { |repo| repo["is_update_repo"] }
    end

    # configure libzypp services to allow online migration
    # (used for activating the default migration setup from the registration server)
    def activate_services
      # disable the update repositories if not required
      if !install_updates
        SwMgmt.set_repos_state(services_repositories(only_updates: true), false)
      end

      activate_solver
    end

    # configure libzypp repositories to allow online migration
    # (used for activating the user changes)
    def activate_repositories
      all_repos = Yast::Pkg.SourceGetCurrent(false)

      all_repos.each do |repo|
        repo_data = Yast::Pkg.SourceGeneralData(repo)

        # enabled migration repositories, disable the others, change
        # the status if it is different than expected
        next if repositories.include?(repo) == repo_data["enabled"]

        # switch the repository state
        new_state = !repo_data["enabled"]
        log.info "#{new_state ? "Enabling" : "Disabling"} repository #{repo_data["alias"]}"
        Yast::Pkg.SourceSetEnabled(repo, new_state)
      end

      activate_solver
    end

    private

    # activate the migration repositories to install the updates
    def activate_solver
      set_solver

      # load the objects from the enabled repositories
      Yast::Pkg.SourceLoad

      # upgrade from all repositories
      Yast::Pkg.PkgUpdateAll({})
      Yast::Pkg.PkgSolve(false)

      select_patches if install_updates
    end

    # set the solver flags for online migration
    # @see https://fate.suse.com/319138
    def set_solver
      log.info "Setting the solver flags for online migration"
      Yast::Pkg.SetSolverFlags("ignoreAlreadyRecommended" => true,
                               "allowVendorChange"        => false)
    end

    # preselect all applicable patches (except optional ones)
    def select_patches
      patches_count = Yast::Pkg.ResolvablePreselectPatches(:all)
      log.info "Preselected patches: #{patches_count}"
    end

    # evaluate migration repositories and services
    # @param [Boolean] only_updates return only the update repositories
    # @return [Array<Fixnum>] list of used migration repositories
    def services_repositories(only_updates: false)
      service_repos = services.map do |service|
        SwMgmt.service_repos(service, only_updates: only_updates)
      end

      service_repos.flatten
    end
  end
end
