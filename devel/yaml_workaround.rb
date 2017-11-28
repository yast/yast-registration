# Monkey Patch to workaround issue in ruby 2.4 Psych (bsc#1048526)
# when fixed or if suseconnect is changed then remove
# (copied from test/spec_helper.rb)
module SUSE
  module Connect
    module Remote
      class Product
        alias_method :initialize_orig, :initialize
        def initialize(arg = {})
          initialize_orig(arg)
        end
      end

      class Service
        alias_method :initialize_orig, :initialize
        def initialize(arg = { "product" => {} })
          initialize_orig(arg)
        end
      end
    end
  end
end
