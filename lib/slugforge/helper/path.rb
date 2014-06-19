require 'bundler'

module Slugforge
  module Helper
    module Path
      def self.included(base)
        base.extend ClassMethods
        base.source_root base.templates_dir
      end

      def project_path(*paths)
        File.join(project_root, *paths)
      end

      def project_root
        return @locate_project unless @locate_project.nil?
        if options[:path] && Dir.exist?(File.expand_path(options[:path]))
          return File.expand_path(options[:path])
        end

        path = File.expand_path(Dir.pwd)
        paths = path.split('/')
        until paths.empty?
          if Dir.exist?(File.join(*paths, '.git'))
            @locate_project = File.join(*paths)
            return @locate_project
          end

          paths.pop
        end
        raise error_class, "Invalid path. Unable to find a .git project anywhere in path #{path}. Specify a path with --path."
      end

      def upstart_dir
        @upstart_conf_dir ||= project_path('deploy', 'upstart').tap do |dir|
                                FileUtils.mkdir_p(dir)
                              end

      end

      def scripts_dir(*paths)
        File.join(self.class.scripts_dir, *paths)
      end

      def templates_dir(*paths)
        File.join(self.class.templates_dir, *paths)
      end

      def deploy_dir(*paths)
        @deploy_dir ||= File.join('/opt', 'apps', project_name)
        File.join(@deploy_dir, *paths)
      end

      def release_dir(*paths)
        deploy_dir('releases', sha)
      end

      def system_with_path(cmd, path=nil)
        path ||= options[:path]
        cwd_command = path ? "cd #{path} && " : ""
        ::Bundler.with_clean_env { system("#{cwd_command}#{cmd}") }
      end

      module ClassMethods
        def scripts_dir
          @scripts_dir ||= File.expand_path('../../../scripts', File.dirname(__FILE__))
        end

        def templates_dir
          @templates_dir ||= File.expand_path('../../../templates', File.dirname(__FILE__))
        end
      end
    end
  end
end

