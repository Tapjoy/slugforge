require 'slugforge/helper/build'
require 'slugforge/helper/config'
require 'slugforge/helper/fog'
require 'slugforge/helper/git'
require 'slugforge/helper/path'
require 'slugforge/helper/project'
require 'slugforge/models/logger'

module Slugforge
  module Helper
    def self.included(base)
      base.send(:include, Slugforge::Helper::Build)
      base.send(:include, Slugforge::Helper::Config)
      base.send(:include, Slugforge::Helper::Fog)
      base.send(:include, Slugforge::Helper::Git)
      base.send(:include, Slugforge::Helper::Path)
      base.send(:include, Slugforge::Helper::Project)
    end

    protected
    def force?
      options[:force] == true
    end

    def json?
      options[:json] == true
    end

    def pretend?
      test? || options[:pretend] == true
    end

    def test?
      options[:test] == true
    end

    def notifications_enabled?
      test? || !pretend?
    end

    def quiet?
      options[:quiet] == true
    end

    def verbose?
      options[:verbose] == true
    end

    def error_class
      json? ? JsonError : Thor::Error
    end

    def elapsed_time
      format_age @command_start_time
    end

    def logger
      @logger ||= begin
                    log_level = if quiet?
                                  :quiet
                                elsif json?
                                  :json
                                elsif verbose?
                                  :verbose
                                end
                    Slugforge::Logger.new(self.shell, log_level)
                  end
    end

    def execute(cmd)
      unless pretend?
        if ruby_version_specified?
          cmd = "rvm #{options[:ruby]} do #{cmd}"
        elsif has_ruby_version_file?
          cmd = "rvm #{get_ruby_version_from_file} do #{cmd}"
        end

        # in thor, if capture is set, it uses backticks to run the command which returns a string.
        # Otherwise they use `system` which returns true or nil if it worked. So check the return value
        # and if it used backticks examine $? which keeps the result of the last command run to see
        # if it worked.
        returned = run(cmd, {:verbose => verbose?, :capture => verbose?})
        if returned.is_a?(String)
          process_status = $?
          logger.say_status :run, "Command result #{process_status.to_s}. Command output: #{returned}", :green
          return process_status.success?
        end

        return returned
      end
      true
    end

    def with_env(env={}, &blk)
      original = ENV.to_hash
      ENV.replace(original.merge(env))

      # Ensure rbenv isn't locked into a version
      if ENV['RBENV_VERSION']
        ENV.delete('RBENV_VERSION')

        # when you use a shim provided by rbenv the $PATH is modified to point to the proper ruby version so shims are
        # bypassed. We need to remove those path entries to totally unset rbenv. We remove every .rbenv path _except_
        # shims so it can still use the correct version defined by .ruby-version.
        paths = ENV['PATH'].split(':').reject do |path|
          path =~ /\.rbenv\/(\w+)/ && !%w(shims bin).include?($1)
        end
        ENV['PATH'] = paths * ':'
      end

      # Ensure RVM isn't locked into a version
      ENV.delete('RUBY_VERSION')
      yield
    ensure
      ENV.replace(original)
    end

    def with_gemfile(gemfile, &blk)
      with_env('BUNDLE_GEMFILE' => gemfile) do
        ENV.delete('GEM_HOME')
        ENV.delete('GEM_PATH')
        ENV.delete('RUBYOPT')
        yield
      end
    end

    def delete_option(options, option)
      result = options.dup
      index = result.index(option)
      if index
        result.delete_at(index)
        result.delete_at(index)
      end
      result
    end

    def delete_switch(options, switch)
      result = options.dup
      index = result.index(option)
      result.delete_at(index) if index
      result
    end

    def format_size(size)
      units = %w(B KB MB GB TB)
      size, unit = units.reduce(size.to_f) do |(fsize, _), utype|
        fsize > 512 ? [fsize / 1024, utype] : (break [fsize, utype])
      end

      "#{size > 9 || size.modulo(1) < 0.1 ? '%d' : '%.1f'} %s" % [size, unit]
    end

    SEGMENTS = {
      :year   => 60 * 60 * 24 * 365,
      :month  => 60 * 60 * 24 * 7 * 4,
      :week   => 60 * 60 * 24 * 7,
      :day    => 60 * 60 * 24,
      :hour   => 60 * 60
    }

    def format_age(age)
      age = Time.now - age
      segments = {}

      SEGMENTS.each do |segment, length|
        next unless age >= length

        segments[segment] = (age / length).floor
        age = age % length
      end

      # We only show Minutes or Seconds if there is no other scope
      if segments.empty?
        segments[:minute] = (age / 60).floor if age >= 60
        segments[:second] = (age % 60).floor
      end

      segments.map do |seg, size|
        plural = 's' if size != 1
        "#{size} #{seg}#{plural}"
      end.join(', ')
    end
  end
end

