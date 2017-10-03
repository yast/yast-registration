# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC
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
require "yast/suse_connect"

module Yast
  # This is just a wrapper around the "migration_repos" client to run it at
  # the upgrade workflow.
  class InstMigrationRepos < Client
    include Yast::Logger
    extend Yast::I18n

    def main
      textdomain "registration"

      Yast.import "Installation"

      # initialize the target path
      set_target_path

      # call the normal client
      Yast::WFM.call("migration_repos")
    end

  private

    # Pass the target directory to SUSEConnect
    def set_target_path
      return if Installation.destdir == "/"

      log.info("Setting SUSEConnect target directory: #{Installation.destdir}")
      SUSE::Connect::System.filesystem_root = Installation.destdir
    end
  end
end

Yast::InstMigrationRepos.new.main
