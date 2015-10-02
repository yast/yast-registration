# ------------------------------------------------------------------------------
# Copyright (c) 2015 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE LLC.
#
# To contact SUSE about this file by physical or electronic mail, you may find
# current contact information at www.suse.com.
# ------------------------------------------------------------------------------

require "yast"

module Registration
  # this class handles activating the new releasever value in the package management
  class Releasever
    include Yast::Logger

    # the environment variable which overrides the system default in libzpp
    RELEASEVER_ENV = "ZYPP_REPO_RELEASEVER"

    Yast.import "Pkg"

    # the new $releasever value
    attr_reader :version

    # has been the $releasever set?
    # @return [Boolean] true if $releasever has been set
    def self.set?
      !ENV[RELEASEVER_ENV].nil?
    end

    # constructor
    # @param [String] version the new release version value
    def initialize(version)
      @version = version
    end

    # activate the new releasever
    def activate
      log.info "Setting $releasever to: #{version}"
      # export the settings
      ENV[RELEASEVER_ENV] = version

      repos = repos_to_refresh
      return if repos.empty?

      # refresh the repositories and reload the packages
      Yast::Pkg.SourceFinishAll
      Yast::Pkg.SourceRestore
      refresh(repos)
      Yast::Pkg.SourceLoad
    end

    private

    # get the repositories which contain "$releasever" directory in the URL
    # @return [Array<Fixnum>] the repository list
    def repos_to_refresh
      repos = Yast::Pkg.SourceGetCurrent(true)
      repos.select! do |repo|
        # check the raw URL (without expanded variables)
        raw_url = Yast::Pkg.SourceGeneralData(repo)["raw_url"]

        next false unless raw_url

        # The URL variables can be encoded is several ways, like $releasever or
        # ${releasever}, there are also $releasever_major and $releasever_minor
        # variables which contain just parts of the $releasever.
        #
        # More over there can be complicated expressions like
        #   SLE_${releasever_major}${releasever_minor:+_SP$releasever_minor}
        # which is expanded to "SLE_12" in SLES12 and to "SLE_12_SP1" in SLES12-SP1.
        #
        # Therefore do a simple check for "$" character here, in the worst case
        # we do an unnecessary refresh which is better than a missing refresh and
        # using the old packages.
        raw_url.include?("$")
      end

      log.info "Found repositories to refresh: #{repos}"
      repos
    end

    # refresh the requested repositories
    # @param [Array<Fixnum>] repos the repositories to refresh
    def refresh(repos)
      repos.each do |repo|
        log.info "Refreshing repository #{repo}"
        Yast::Pkg.SourceForceRefreshNow(repo)
      end
    end
  end
end
