source 'https://rubygems.org'

gemspec

# custom fpm version from gemfury, see also: the thor comment below
# The public version is compatible as well
gem 'fpm', '~> 1.1'

gem 'rake'

# unit test output for CI. Can't be in test/develop
gem 'ci_reporter', '~> 1.9.0'

# We've cut a custom version of Thor (0.18.1.1), this is the SHA that version is cut from.
# TODO: make sure we remove this when we can bump Thor to a version >= 0.18.2
# This has to be commented out, since our custom version conflicts with the version in GH
#gem 'thor', :github => 'erikhuda/thor', :ref => '12f767bdd8973a2cc6501b00ec459d10a17e0eeb'
gem 'thor'

group :test do
  gem 'simplecov'
  gem 'fakefs', require: 'fakefs/safe'
end
