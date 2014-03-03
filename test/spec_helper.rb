if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end

$:.unshift(File.expand_path("../../src/lib", __FILE__))
