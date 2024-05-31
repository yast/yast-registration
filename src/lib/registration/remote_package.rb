# Copyright (c) [2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

module Registration
  # Represents a package as seen through the SUSE::Connect API
  #
  # Additionally, it offers a mechanism to find out the local package (libzypp counterpart).
  #
  # @example Find the status
  class RemotePackage
    attr_reader :id, :name, :arch, :version, :release, :addon, :status

    # @param id      [Integer] Package ID
    # @param name    [String] Package name
    # @param arch    [String] Architecture
    # @param version [String] Version number
    # @param release [String] Release number
    # @param addon   [Addon]  Addon which the package belongs to
    # @param status  [Symbol] Package status
    # rubocop:disable Metrics/ParameterLists
    def initialize(id:, name:, arch:, version:, release:, addon:, status: nil)
      @id = id
      @name = name
      @arch = arch
      @version = version
      @release = release
      @addon = addon
      @status = status
    end
    # rubocop:enable Metrics/ParameterLists

    def full_version
      "#{version}-#{release}"
    end

    def select!
      return if selected?

      @old_status = @status
      @status = :selected
    end

    def unselect!
      @status = @old_status || :unknown if selected?
    end

    def installed?
      status == :installed
    end

    def selected?
      @status == :selected
    end
  end
end
