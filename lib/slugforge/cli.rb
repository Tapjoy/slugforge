require 'thor'
require 'slugforge/helper'
require 'slugforge/commands'

# Don't display warnings to the user
$VERBOSE = nil

$stdout.sync = true

module Slugforge
  class Cli < Slugforge::Command

    desc 'version', 'display the current version'
    def version
      logger.say_json :slugforge => Slugforge::VERSION
      logger.say "slugforge #{Slugforge::VERSION}"
    end

    desc 'build [ARGS]', 'build a new slug (`slugforge build` for more help)'
    option :ruby, :type => :string, :aliases => '-r',
      :desc => 'Ruby version this package requires'
    option :path, :type => :string, :default => Dir.pwd,
      :desc => 'The path to the files being packaged'
    option :clean, :type => :boolean,
      :desc => 'Clean existing slugs from current directory before build'
    option :deploy, :type => :string,
      :desc => 'Deploy the slug if the build was successful'
    option :'with-git', :type => :boolean,
      :desc => 'include the .git folder in the slug'
    def build
      verify_procfile_exists!
      invoke Slugforge::Commands::Build
    end

    desc 'deploy <command> [ARGS]', 'deploy a slug to a host (`slugforge deploy` for more help)'
    subcommand 'deploy', Slugforge::Commands::Deploy

    desc 'project <command> [ARGS]', 'manage projects (`slugforge project` for more help)'
    subcommand 'project', Slugforge::Commands::Project

    desc 'tag <command> [ARGS]', 'manage project tags (`slugforge tag` for more help)'
    subcommand 'tag', Slugforge::Commands::Tag

    desc 'wrangler <command> [ARGS]', 'list, push and delete slugs (`slugforge wrangler` for more help)'
    subcommand 'wrangler', Slugforge::Commands::Wrangler

    # subcommand method name is configuration to not conflict with the config method on all commands
    desc 'config <command> [ARGS]', 'configure slugforge (`slugforge config` for more help)'
    subcommand 'configuration', Slugforge::Commands::Config

    def help(command = nil, subcommand = nil)
      return super if command

      self.class.help(shell, subcommand)

      logger.say <<-HELP
Project Naming

  The easiest way to name a project is to name it after a repository. The only reason you may have to use a different
  name is for testing of some kind. That said, once you've named your project there are a few ways for slugforge to
  determine what project you are attempting to run project-specific commands (such as build) against. There are two
  basic ways of telling slugforge which project you are working with:

    1. With the provided configuration option (through a CLI flag, environment variable or config file)
    2. By running the slugforge command from inside the project's repository. slugforge will use the name of the
       project's root folder (as defined by the location of .git), which generally matches the name of the repository
       which should be the name of the project in slugforge.

Configuring the CLI

  The configuration options above can all be configured through several candidate configuration files, environment
  variables or the flags as shown. Precedence is by proximity to the command: flags trump environment, which trumps
  configuration files. Slugforge will attempt to load configuration files in the following locations, listed in order
  of priority highest to lowest:

    .slugforge
    ~/.slugforge
    /etc/slugforge

  Configuration files are written in yaml for simplicity. Below is a list of each option and the keys expected for each
  type. File keys should be split on periods and expanded into hashes. AWS buckets accepts a comma seperated list,
  which will be tried from first to last. There is an example config at the end of this screen.

      HELP

      rows = []
      rows << %w(CLI Environment File)
      Slugforge::Configuration.options.each do |name, config|
        rows << [config[:option], config[:env], config[:key]]

        unless rows.last.first.nil?
          rows.last[0] = "--#{rows.last.first}"
        end
      end
      print_table(rows, :indent => 4)

      logger.say <<-HELP

Example configuration file

    aws:
      access_key: hashhashhashhashhash
      secret_key: hashhashhashhashhashhashhashhashhashhash

      HELP
    end

    if binding.respond_to?(:pry)
      desc 'pry', 'start a pry session inside of a Thor command', :hide => true
      option :path, :type => :string, :default => Dir.pwd,
        :desc => 'The path to the files being packaged'
      def pry
        binding.pry
      end
    end

    desc 'debug', 'run a test command inside slugforge', :hide => true
    option :path, :type => :string, :default => Dir.pwd,
      :desc => 'The path to the files being packaged'
    def debug(cmd)
      eval(cmd)
    end
  end
end

