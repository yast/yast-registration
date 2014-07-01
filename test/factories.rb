require "registration/addon"
require "suse/connect"

def suse_connect_product_generator(attrs={})
    params = {}
    params["available"] = attrs["available"] if attrs.has_key?("available")
    params['name'] = attrs['name'] || "Product#{rand(100000)}"
    params['friendly_name'] = attrs['friendly_name'] || "The best cool #{params['name']}"
    params['description'] = attrs['description'] || "Bla bla bla bla!"
    params["id"] = attrs["id"] || "#{rand(10000)}"
    params['identifier'] = attrs['zypper_name'] || "prod#{rand(100000)}"
    params['version'] = attrs['version'] || "#{rand(13)}"
    params['arch'] = attrs['arch'] || "x86_64"
    params['free'] = attrs.fetch('free', true)
    params['eula_url'] = attrs['eula_url']
    params["extensions"] = attrs['extensions'] || []

    params
end

def addon_generator(params={})
  SUSE::Connect::Remote::Product.new(suse_connect_product_generator(params))
end

def addon_with_child_generator(parent_params={})
  prod_child = suse_connect_product_generator
  SUSE::Connect::Remote::Product.new(suse_connect_product_generator(parent_params.merge('extensions' => [prod_child])))
end

# add cache reset, which is not needed in runtime, but for test it is critical
class Registration::Addon
  class << self
    def reset_cache
      @cached_addons = nil
      @registered = nil
      @selected = nil
    end
  end
end

def addon_reset_cache
  Registration::Addon.reset_cache
end
