source "https://rubygems.org"

# FIXME: use a correct branch here...
gem "suse-connect", github: "SUSE/connect", branch: "v0.2.17"

group :test do
  gem "rake"
  gem "yard"
  gem "yast-rake", ">= 0.1.9"
  gem "rspec", "~> 2.14.0"
  gem "gettext", require: false
  gem "rubocop", "~> 0.27.0", require: false
  gem "simplecov", require: false
  gem "coveralls", require: false if ENV["TRAVIS"]
end
