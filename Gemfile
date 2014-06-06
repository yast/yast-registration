source "https://rubygems.org"

gem "suse-connect", ">= 0.0.19", :github => "SUSE/connect"

group :test do
  gem "rake"
  gem "rspec", "~> 2.14.0"
  gem "simplecov", :require => false
  gem "coveralls", :require => false if ENV["TRAVIS"]
end
