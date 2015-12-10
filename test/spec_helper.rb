if ENV["COVERAGE"]
  require "simplecov"

  formatters = [ SimpleCov::Formatter::HTMLFormatter ]
  # use coveralls for on-line code coverage reporting at Travis CI
  if ENV["TRAVIS"]
    require "coveralls"
    formatters << Coveralls::SimpleCov::Formatter
  end

  # optionally generate lcov output if it is present
  begin
    require "simplecov-lcov"
    SimpleCov::Formatter::LcovFormatter.report_with_single_file = true
    formatters << SimpleCov::Formatter::LcovFormatter
  rescue LoadError
  end
  
  SimpleCov.formatters = formatters

  SimpleCov.start do
    add_filter "/test/"
  end
end

# configure RSpec
RSpec.configure do |config|
  config.mock_with :rspec do |c|
    # https://relishapp.com/rspec/rspec-mocks/v/3-0/docs/verifying-doubles/partial-doubles
    c.verify_partial_doubles = true
  end
end

libdir = File.expand_path("../../src/lib", __FILE__)
$LOAD_PATH.unshift(libdir)

ENV["Y2DIR"] = File.expand_path("../../src", __FILE__)

def fixtures_file(file)
  File.expand_path(File.join("../fixtures", file), __FILE__)
end

require "yaml"
def load_yaml_fixture(file)
  YAML.load_file(fixtures_file(file))
end

# load data generators
require_relative "factories"

# force loading all files to report proper code coverage
Dir.chdir(libdir) { Dir["**/*.rb"].each { |f| require f } }
