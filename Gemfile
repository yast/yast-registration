source "https://rubygems.org"

gem "suse-connect", :github => "SUSE/connect"

group :test do
  gem "rake"
  gem "rspec"
  gem "simplecov", :require => false
  gem "coveralls", :require => false if ENV["TRAVIS"]
end
