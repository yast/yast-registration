# allow to register against products defined in yaml. Very similar concept to online medium just this time
# for first boot purpose

require "yaml"
require "yast"

module Registration
  Yast.import "Arch"

  # UI should use {.available_products} and pass the user's choice to
  # {.select_product}
  #
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

    # @param product_name [String, nil] nil in case no product is selected, so no registration
    def self.select_product(product_name)
      product = available_products.find{ |p| p["name"] == product_name }

      @manually_selected = true
      @selected_product = product
    end

    def self.selected_product
      return @selected_product if @manually_selected

      product = available_products.find{ |p| p["default"] }
      product ||= available_products.first # use first if none have default

      select_product(product["name"])
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
