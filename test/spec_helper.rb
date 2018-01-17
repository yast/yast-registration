require "pathname"

TESTS_PATH = Pathname.new(File.dirname(__FILE__))
FIXTURES_PATH = TESTS_PATH.join("fixtures")

if ENV["COVERAGE"]
  require "simplecov"

  # use coveralls for on-line code coverage reporting at Travis CI
  if ENV["TRAVIS"]
    require "coveralls"

    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
      SimpleCov::Formatter::HTMLFormatter,
      Coveralls::SimpleCov::Formatter
    ]
  end

  src_location = File.expand_path("../../src", __FILE__)
  # track all ruby files under src
  SimpleCov.track_files("#{src_location}/**/*.rb")

  SimpleCov.start do
    add_filter "/test/"
  end
end

srcdir = File.expand_path("../../src", __FILE__)
y2dirs = ENV.fetch("Y2DIR", "").split(":")
ENV["Y2DIR"] = y2dirs.unshift(srcdir).join(":")

libdir = "#{srcdir}/lib"
$LOAD_PATH.unshift(libdir)

require "suse/connect"

# Monkey Patch to workaround issue in ruby 2.4 Psych (bsc#1048526)
# when fixed or if suseconnect will be changed, then remove
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

def fixtures_file(file)
  FIXTURES_PATH.join(file).to_s
end

require "yaml"
def load_yaml_fixture(file)
  YAML.load_file(fixtures_file(file))
end

require "yast"
require "y2packager/product"
def stub_product_selection
  name = "AutoinstFunctions"
  Yast.const_set name.to_sym, Class.new {
    def self.selected_product
      Y2Packager::Product.new(name: "SLES", short_name: "SLES15")
    end
  }
end

stub_product_selection

# load data generators
require_relative "factories"

# force loading all files to report proper code coverage
Dir.chdir(libdir) { Dir["**/*.rb"].each { |f| require f } }

# configure RSpec
RSpec.configure do |config|
  config.mock_with :rspec do |c|
    # https://relishapp.com/rspec/rspec-mocks/v/3-0/docs/verifying-doubles/partial-doubles
    c.verify_partial_doubles = true
  end

  config.extend Yast::I18n # available in context/describe
  config.include Yast::I18n # available in it/let/before
end
