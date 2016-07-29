source "https://rubygems.org"

gem "suse-connect", github: "SUSE/connect", branch: "master"

group :test do
  gem "rake"
  gem "yard"
  gem "yast-rake", ">= 0.1.9"
  gem "rspec", "~> 3.3.0"
  gem "gettext", require: false
  gem "rubocop", "~> 0.41.2", require: false
  gem "simplecov", require: false
  gem "coveralls", require: false if ENV["TRAVIS"]
  gem "cheetah"
end
