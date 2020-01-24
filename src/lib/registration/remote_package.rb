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
    attr_reader :name, :arch, :version, :release, :addon

    # @param name    [String] Package name
    # @param arch    [String] Architecture
    # @param version [String] Version number
    # @param release [String] Release number
    # @param addon   [Addon]  Addon which the package belongs to
    def initialize(name:, arch:, version:, release:, addon:)
      @name = name
      @arch = arch
      @version = version
      @release = release
      @addon = addon
    end

    def full_version
      "#{version}-#{release}"
    end

    def select!
      @old_status = @status
      @status = :selected
    end

    def unselect!
      @status = @old_status if selected?
    end

    def installed?
      status == :installed
    end

    def selected?
      @status == :selected
    end

    # Returns the package's status
    #
    # @return [Symbol] Package status (:available, :installed, etc.). :unknown
    #   when there is no libzypp counterpart.
    def status
      return @status if @status
      # TODO: Determine the correct status when the libzypp_package is not
      # available. It might depend on whether the addon is registered/selected
      # or not.
      return :unknown unless libzypp_package
      @status ||= libzypp_package.status
    end

    # @return [Y2Packager::Package,nil] Local package (libzypp) counterpart
    def libzypp_package
      return @libzypp_package if @libzypp_package
      candidates = Y2Packager::Package.find(name)
      return nil if candidates.nil?
      # FIXME: Check the version too
      @libzypp_package = candidates.first
    end
  end
end
