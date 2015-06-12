
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
  # this class displays and runs the dialog with addon selection
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

    Yast.import "Pkg"

    attr_accessor :repositories, :install_updates

    def initialize
      self.repositories = []
    end

    def add_service(service_name)
      service_repos = SwMgmt.service_repos(service_name)
      repositories.concat(service_repos)
    end

    def activate
      # be compatible with "zypper dup --from"
      log.info "Disabling recommended packages for already installed packages"
      Yast::Pkg.SetSolverFlags("ignoreAlreadyRecommended" => true)

      log.info "Adding upgrade repos: #{repositories.map { |repo| repo["alias"] }}"
      repositories.each { |repo| Yast::Pkg.AddUpgradeRepo(repo["SrcId"]) }

      Yast::Pkg.PkgSolve(false)

      return unless install_updates

      # preselect all applicable patches (except optional ones)
      patches_count = Yast::Pkg.ResolvablePreselectPatches(:all)
      log.info "Preselected patches: #{patches_count}"
    end
  end
end
