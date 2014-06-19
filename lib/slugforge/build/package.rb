module Slugforge
  module Build
    class Package < Slugforge::BuildCommand
      desc :package, 'package the project'
      def call
        existing = Dir.glob('*.slug')

        if options[:clean]
          existing.each do |path|
            logger.say_status :clean, path, :red
            File.delete(path)
          end
        end

        logger.say_status :execute, "fpm #{package_file_name}"
        execute(fpm_command)

        if options[:deploy]
          invoke Slugforge::Commands::Deploy, [:file, package_file_name, options[:deploy]], []
        end
      end
      default_task :call

      private
      def fpm_command
        command = ['fpm']
        command << '--verbose'
        command << "--package #{package_file_name}"
        command << "--maintainer=#{`whoami`.chomp}"
        command << "-C #{project_root}"
        command << '-s dir'
        command << '-t sh'
        command << "-n #{project_name}"
        command << "-v #{date_stamp}"
        command << '--template-scripts'
        command << post_install_template_variables
        command << "--after-install #{post_install_script_path}"
        unless options[:'with-git']
          command << "--exclude '.git'"
          command << "--exclude '.git/**'"
        end
        command << "--exclude '*.slug'"
        command << "--exclude 'log/**'"
        command << "--exclude 'tmp/**'"
        command << "--exclude 'vendor/bundle/ruby/1.9.1/cache/*'"
        command << "." # package all the things
        command.join(' ')
      end

      def post_install_script_path
        scripts_dir('post-install.sh')
      end

      def post_install_template_variables
        variables = {
          'release_id' => File.basename(package_file_name, ".*")
        }.map do |key, value|
          "--template-value #{key}=#{value}"
        end.join(' ')
      end
    end
  end
end
