module Slugforge
  module Build
    class ExportUpstart < Slugforge::BuildCommand
      desc :call, 'export upstart scripts from the Procfile'
      def call
        unless File.exist?(procfile_path)
          logger.say_status :missing, 'foreman Procfile', :yellow
          return false
        end

        logger.say_status :execute, 'preprocessing foreman templates'
        preprocess_templates
      end
      default_task :call

      private
      def preprocess_templates
        Dir.foreach(foreman_templates_dir) do |template|
          next unless template =~ /\.erb$/

          template "foreman/#{template}", File.join(upstart_templates_dir, template)
        end
      end

      # The template file is processed by ERB twice. Once by chef when putting it down
      # and once by foreman when generating the upstart config. This ERB string goes into
      # the command variable so it will show up as it is here when chef is done with it
      # so foreman can process the logic in this string.
      def template_command
        if unicorn_command
          "<% if process.command.include?('bundle exec #{unicorn_command}') %> deploy/unicorn-shepherd.sh #{unicorn_command} <%= app %>-<%= name %>-<%= num %> <% else %> <%= process.command %> <% end %>"
        else
          "<%= process.command %>"
        end

      end

      # iterate through procfile and see if we have have unicorn or rainbows
      #
      # ===Returns===
      # unicorn|rainbows or nil if neither was found
      #
      # Notes, currently doesn't handle if there is both unicorn AND rainbows. Will just return
      # the last one it finds. We could handle this if someone needed it but this is
      # easier for now.
      def unicorn_command
        @unicorn_command ||= begin
          command = nil
          ::File.read(procfile_path).lines do |line|
            if line.include?("bundle exec unicorn")
              command = "unicorn"
            elsif line.include?("bundle exec rainbows")
              command = "rainbows"
            end
          end
          # If we are using unicorn/rainbows, put the unicorn-shepherd script into the repo's deploy directory
          # so we can use it to start unicorn as an upstart service
          if command
            FileUtils.cp(unicorn_shepherd_path, project_path('deploy'))
          end
          command
        end
      end

      def foreman_templates_dir
        templates_dir('foreman')
      end

      def procfile_path
        project_path('Procfile')
      end

      def unicorn_shepherd_path
        scripts_dir('unicorn-shepherd.sh')
      end

      def upstart_templates_dir
        @repo_templates_dir ||= project_path('deploy', 'upstart-templates').tap do |dir|
                                  FileUtils.mkdir_p(dir)
                                end
      end
    end
  end
end

