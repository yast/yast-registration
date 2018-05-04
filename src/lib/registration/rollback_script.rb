# ------------------------------------------------------------------------------
# Copyright (c) 2018 SUSE LLC
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

require "yast"
require "fileutils"

module Registration
  # This class handles creating a registration rollback script  which is called
  # when the upgrade is aborted or YaST crashes. The script body is stored
  # in the data/registration/registration_rollback.sh file.
  class RollbackScript
    include Yast::Logger

    BACKUP_DIR = "var/adm/backup/system-upgrade".freeze

    # use number 0200, the original repositories need to be restored first,
    # they are stored in script with number 0100
    DEFAULT_SCRIPT_NAME = "restore-0200-registration.sh".freeze

    SUSE_CONNECT = "/usr/sbin/SUSEConnect".freeze

    attr_reader :root

    # @param root [String] target root
    def initialize(root: "/mnt")
      @root = root
    end

    # create the registration rollback script
    # @note The script can be created only when the target root is mounted.
    def create
      log.info "Creating registration rollback script #{script_path}"
      src_file = File.expand_path("../../../data/registration/registration_rollback.sh", __FILE__)
      ::FileUtils.cp(src_file, script_path)
    end

    # delete the script
    def delete
      return unless File.exist?(script_path)

      log.info "Removing the registration rollback script (#{script_path})"
      File.delete(script_path)
    end

    # can the rollback script be applied?
    def applicable?
      # check if the SUSEConnect tool is present, it might not be installed
      # or not available at all (when upgrading from SLE11)
      ret = File.exist?(File.join(root, SUSE_CONNECT))
      log.info("File #{SUSE_CONNECT} found at #{root}: #{ret}")
      ret
    end

    # full path to the script
    # @return [String] path
    def script_path
      @path ||= File.join(root, BACKUP_DIR, DEFAULT_SCRIPT_NAME)
    end
  end
end
