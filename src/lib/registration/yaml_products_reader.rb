# Copyright (c) [2022] SUSE LLC
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

require "yaml"
require "yast"

module Registration
  Yast.import "Arch"

  # Reads products defined by YAML file
  #
  # Added for SLED registration on a WSL SLES image (jsc#PED-1380).
  class YamlProductsReader
    attr_reader :path

    def initialize(path = DEFAULT_PATH)
      @path = path
    end

    # @return [Array<Hash>]
    def read
      return [] unless yaml_exist?

      YAML.load_file(path).map { |p| transform(p) }
    end

  private

    DEFAULT_PATH = "/etc/YaST2/products.yaml".freeze
    private_constant :DEFAULT_PATH

    # check if yaml products are defined at all
    def yaml_exist?
      ::File.exist?(path)
    end

    # For all values:
    #   - converts them to String (to allow writing "15.4" as 15.4)
    #   - replaces $arch substring with the current architecture
    # And also:
    #   - replaces version with version_version as registration expects
    #   - adds arch key if not defined
    #   - converts value of default key to boolean
    #
    # @param product [Hash]
    # @return [Hash] A new transformed hash
    def transform(product)
      arch = Yast::Arch.rpm_arch

      res = product.map do |key, val|
        val_s = val.to_s.gsub("$arch", arch)
        [key, val_s]
      end.to_h
      res["version_version"] ||= res["version"]
      res["arch"] ||= arch
      res["default"] = res["default"]&.casecmp?("true") ? true : false

      res
    end
  end
end
