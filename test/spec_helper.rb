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

  SimpleCov.start do
    add_filter "/test/"
  end
end

libdir = File.expand_path("../../src/lib", __FILE__)
$LOAD_PATH.unshift(libdir)

ENV["Y2DIR"] = File.expand_path("../../src", __FILE__)

def fixtures_file(file)
  FIXTURES_PATH.join(file).to_s
end

require "yaml"
def load_yaml_fixture(file)
  YAML.load_file(fixtures_file(file))
end

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
