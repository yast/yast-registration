source "https://rubygems.org"

gem "scc_api", :github => "yast/rubygem-scc_api"

group :test do
  gem "rake"
  gem "rspec"
  gem "simplecov", :require => false
  gem "coveralls", :require => false if ENV["TRAVIS"]
end
