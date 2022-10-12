# allow to register against products defined in yaml. Very similar concept to online medium just this time
# for first boot purpose

require "yaml"
require "yast"

module Registration
  Yast.import "Arch"

  # Added for SLED registration on a WSL SLES image, see
  # https://jira.suse.com/browse/PED-1380
  class YamlProduct
    PATH = "/etc/YaST2/products.yaml"

    # check if yaml products are defined at all
    def self.exist?
      ::File.exist?(PATH)
    end

    def self.available_products
      return @products if @products
      return nil unless exist?

      @products = YAML.load_file(PATH)
      @products = @products.map { |p| expand_variables(p) }
    end

    def self.selected_product
      return nil unless exist?

      # TODO: really select
      {
        "display_name" => "SUSE Linux Enterprise Desktop 15 SP5",
        "name" => "SLED",
        "arch" => "x86_64",
        "version" => "15.4-0",
        "version_version" => "15.4",
        "register_target" => "sle-15-x86_64"
      }
    end

    private

    # For all values:
    # - convert them to String (to allow writing "15.4" as 15.4)
    # - replace $arch substrings with the architecture
    # @param product [Hash]
    # @return [Hash] new hash
    def self.expand_variables(product)
      arch = Yast::Arch.architecture

      product.map do |key, val|
        val_s = val.to_s
        val_s.gsub!("$arch", arch)
        [key, val_s]
      end.to_h
    end
  end
end
