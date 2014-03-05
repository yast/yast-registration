if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end

$:.unshift(File.expand_path("../../src/lib", __FILE__))

ENV["Y2DIR"] = File.expand_path("../../src", __FILE__)
