# allow to register against products defined in yaml. Very similar concept to online medium just this time
# for first boot purpose

require "yaml"

module Registration
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
    end

    def self.selected_product
      return nil unless exist?

      # TODO: really select
      {
        "display_name" => "SUSE Linux Enterprise Desktop 15 SP5"
        "name" => "SLED",
        "arch" => "x86_64",
        "version" => "15.4",
        "register_target" => "sle-15-x86_64"
      }
    end
  end
end
