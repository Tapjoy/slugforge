if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter "/spec/"
  end
end

$: << File.expand_path('../../lib', __FILE__)
require 'slugforge'
require 'fakefs/spec_helpers'

ENV["THOR_DEBUG"] = "1"

# Load support files
Dir[File.expand_path('../support/**/*.rb', __FILE__)].each { |f| require f }

def fixture_file(file)
  File.expand_path(File.join("../fixtures", file), __FILE__)
end

def with_env(env)
  old_env = env.reduce({}) { |old,(k,v)| old[k] = ENV[k]; ENV[k] = v; old }
  yield
  old_env.each { |k,v| ENV[k] = v }
end

RSpec.configure do |config|
  config.before(:all) do
    Slugforge::Configuration.configuration_files = [ 'slugforge.yml' ]

    sanitize_environment! /AWS_|EC2_|S3_|JENKINS_|SLUGFORGE_/
  end

  config.include FakeFS::SpecHelpers
  config.include HelperProvider
  config.include ConfigurationWriter
end
