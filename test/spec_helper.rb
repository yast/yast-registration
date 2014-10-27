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

  SimpleCov.start
end

# allow only the new "expect" RSpec syntax
RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with :rspec do |c|
    c.syntax = :expect
  end
end

$:.unshift(File.expand_path("../../src/lib", __FILE__))

ENV["Y2DIR"] = File.expand_path("../../src", __FILE__)

def fixtures_file(file)
  File.expand_path(File.join("../fixtures", file), __FILE__)
end

# load data generators
require_relative "factories"

# force loading all files to report proper code coverage
Dir["src/lib/**/*.rb"].each do |file|
  require "./#{file}"
end
