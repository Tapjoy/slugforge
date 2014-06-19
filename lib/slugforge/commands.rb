module Slugforge
  module Commands
    autoload :Build,    'slugforge/commands/build'
    autoload :Config,   'slugforge/commands/config'
    autoload :Deploy,   'slugforge/commands/deploy'
    autoload :Project,  'slugforge/commands/project'
    autoload :Tag,      'slugforge/commands/tag'
    autoload :Tjs,      'slugforge/commands/tjs'
    autoload :Wrangler, 'slugforge/commands/wrangler'
  end

  class JsonError < Thor::Error
    def initialize(message)
      super({error: message}.to_json)
    end
  end

  class Command < Thor
    include Thor::Actions
    include Slugforge::Helper

    check_unknown_options!

    # Add Thor::Actions options
    add_runtime_options!


    class << self
      # Parses the command and options from the given args, instantiate the class
      # and invoke the command. This method is used when the arguments must be parsed
      # from an array. If you are inside Ruby and want to use a Thor class, you
      # can simply initialize it:
      #
      #   script = MyScript.new(args, options, config)
      #   script.invoke(:command, first_arg, second_arg, third_arg)
      #
      def start(given_args=ARGV, config={})
        # Loads enabled slugins. This must be done before the CLI is instantiated so that new commands
        # will be found. Activation of slugins must be delayed until the command line options are parsed
        # so that the full config will be available.
        Configuration.new
        super
      end
    end

    # ==== Parameters
    # args<Array[Object]>:: An array of objects. The objects are applied to their
    #                       respective accessors declared with <tt>argument</tt>.
    #
    # options<Hash>:: Either an array of command-line options requiring parsing or
    #                 a hash of pre-parsed options.
    #
    # config<Hash>:: Configuration for this Thor class.
    #
    def initialize(args=[], options=[], config={})
      @command_start_time = Time.now()

      super

      # Configuration must be
      #  - created after command line is parsed (so not in #start)
      #  - inherited from parent commands
      if config[:invoked_via_subcommand]
        @config = config[:shell].base.config
      else
        @config = Configuration.new(self.options)
        @config.activate_slugins
      end
    end

    protected

    def config
      @config
    end

    def self.exit_on_failure?
      true
    end

    def self.inherited(base)
      base.source_root templates_dir
    end

    def publish(event, *args)
      ActiveSupport::Notifications.publish(event, self, *args) if notifications_enabled?
    rescue => e
      clean_trace = e.backtrace.reject { |l| l =~ /active_support|thor|bin\/slugforge/ } # reject parts of the stack containing active_support, thor, or bin/slugforge
      logger.say_status :error, "[notification #{args.first}] #{e.message}\n" + clean_trace.join("\n"), :red
    end
  end

  # This class overrides #banner, forcing the subcommand parameter to be true by default. This gets around a bug in
  # Thor, and causes subcommands to properly display their parent command in the help text for the subcommand.
  class SubCommand < Command
    def self.banner(command, namespace = nil, subcommand = true)
      super
    end
  end

  class BuildCommand < Command
    class_option :ruby, :type => :string, :aliases => '-r',
      :desc => 'Ruby version this package requires'
    class_option :path, :type => :string, :default => Dir.pwd,
      :desc => 'The path to the files being packaged'
    class_option :clean, :type => :boolean,
      :desc => 'Clean existing slugs from current directory before build'
    class_option :deploy, :type => :string,
      :desc => 'Deploy the slug if the build was successful'
    class_option :'with-git', :type => :boolean,
      :desc => 'include the .git folder in the slug'

    def self.inherited(base)
      base.source_root templates_dir
    end
  end

  class Group < Thor::Group
    include Thor::Actions
    include Slugforge::Helper

    # Add Thor::Actions options
    add_runtime_options!

    def self.inherited(base)
      base.source_root templates_dir
    end
  end
end

