# allow to register against products defined in yaml. Very similar concept to online medium just this time
# for first boot purpose

require "yaml"
require "yast"

module Registration
  Yast.import "Arch"

  # Added for SLED registration on a WSL SLES image, see
  # https://jira.suse.com/browse/PED-1380
  class YamlProductsReader
    attr_reader :path

    def initialize(path = DEFAULT_PATH)
      @path = path
    end

    # @return [Array<Hash>]
    def read
      return [] unless yaml_exist?

      YAML.load_file(path).map { |p| expand_variables(p) }
    end

    private

    DEFAULT_PATH = "/etc/YaST2/products.yaml".freeze
    private_constant :DEFAULT_PATH

    # check if yaml products are defined at all
    def yaml_exist?
      ::File.exist?(path)
    end

    # For all values:
    # - convert them to String (to allow writing "15.4" as 15.4)
    # - replace $arch substrings with the architecture
    # @param product [Hash]
    # @return [Hash] new hash
    def expand_variables(product)
      arch = Yast::Arch.rpm_arch

      product.map do |key, val|
        val_s = val.to_s
        val_s.gsub!("$arch", arch)
        [key, val_s]
      end.to_h
    end
  end
end
