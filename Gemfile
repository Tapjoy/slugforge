source 'https://rubygems.org'

gemspec

gem 'fpm', '~> 1.3'

gem 'fog', '~> 1.23'

gem 'rake'

# unit test output for CI. Can't be in test/develop
gem 'ci_reporter', '~> 1.9.0'

gem 'thor', '~> 0.19'

group :test do
  gem 'simplecov'
  gem 'fakefs', require: 'fakefs/safe'
  gem 'rspec-instrumentation-matcher'
end
