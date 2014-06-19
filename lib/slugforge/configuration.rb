require 'singleton'
require 'forwardable'
require 'slugforge/slugins'

module Slugforge
  # Handles loading configuration data from files and the environment. Order of precedence:
  #
  # 1) ENV
  # 2) `pwd`/.slugforge
  # 3) $HOME/.slugforge
  # 4) /etc/slugforge
  #
  # We load in reverse order, allowing us to simply overwrite values whenever found.
  class Configuration
    extend Forwardable

    class << self
      attr_accessor :configuration_files
    end
    self.configuration_files = [ '/etc/slugforge', File.join(ENV['HOME'], '.slugforge'), File.join(Dir.pwd, '.slugforge') ]

    class <<self
      def options
        @options ||= {}
      end

      def option(name, config)
        raise "configuration option #{name} has already been defined" if options.key?(name)

        options[name] = config
        define_method(name) { values[name] }
      end
    end

    option :aws_access_key,    :key => 'aws.access_key',  :option => :'aws-access-key-id', :env => 'AWS_ACCESS_KEY_ID'
    option :aws_secret_key,    :key => 'aws.secret_key',  :option => :'aws-secret-key',    :env => 'AWS_SECRET_ACCESS_KEY'
    option :ec2_region,        :key => 'ec2.region',      :option => :'ec2-region',        :env => 'EC2_REGION', :default => 'us-east-1'
    option :slug_bucket,       :key => 'aws.slug_bucket', :option => :'slug-bucket',       :env => 'SLUG_BUCKET'
    option :aws_session_token, :option => :'aws-session-token'

    option :project, :key => 'slugforge.project', :option => :project, :env => 'SLUGFORGE_PROJECT'

    option :ssh_username, :key => 'ssh.username', :option => :'ssh-username', :env => 'SSH_USERNAME'

    option :disable_slugins, :key => 'disable_slugins', :option => :'disable-slugins', :env => 'DISABLE_SLUGINS'

    attr_reader :values

    def initialize(options = {})
      @slugin_manager = SluginManager.new
      self.load
      update_from_options options
    end

    def_delegators :@slugin_manager, :load_slugins, :locate_slugins, :slugins

    # Get a hash of all options with default values. The list of values is initialized with the result.
    def defaults
      @values = Hash[self.class.options.select { |_, c| c.key?(:default) }.map { |n,c| [n, c[:default]] }].merge(@values)
    end

    def activate_slugins
      @slugin_manager.activate_slugins(self) unless disable_slugins
    end

    protected
    def load
      # Read configuration files to load list of slugins. Load the slugin classes so that
      # their configuration options are added and reload the configs to populate the new
      # options.
      @values = {}
      load_configuration_files
      defaults

      locate_slugins
      #TODO: disable individual slugins via configuration
      load_slugins unless disable_slugins

      load_configuration_files
      read_env
    end

    def load_configuration_files
      self.class.configuration_files.each { |f| read_yaml f }
    end

    # Attempt to read option keys from a YAML file
    def read_yaml(path)
      return unless File.exist?(path)
      source = YAML.load_file(path)
      return unless source.is_a?(Hash)

      update_with { |config| read_yaml_key(source, config[:key]) }
    end

    # Split a dot-separated key and locate the value from a hash loaded by YAML.
    #   eg. `aws.bucket` looks for `source['aws']['bucket']`.
    def read_yaml_key(source, key)
      return unless key.is_a?(String)
      paths = key.split('.')
      source = source[paths.shift] until paths.empty? || source.nil?
      source
    end

    # Attempt to read option keys from the environment
    def read_env
      update_with { |config| config[:env] && ENV[config[:env]] }
    end

    # Update values with a hash of options.
    def update_from_options(options={})
      update_with { |config| config[:option] && options[config[:option]] }
    end

    # For every option we yield the configuration and expect a value back. If the block returns a value we set the
    # option to it.
    def update_with(&blk)
      self.class.options.each do |name, config|
        value = yield(config)
        @values[name] = value unless value.nil?
      end
    end
  end
end

