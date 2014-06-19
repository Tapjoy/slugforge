module Slugforge
  module Build
    class BuildProject < Slugforge::BuildCommand
      desc :call, 'run a project\'s build script'
      def call
        unless File.exists?(build_script)
          logger.say_status :missing, build_script, :yellow
          return true
        end

        logger.say_status :run, build_script
        inside(project_root) do
          with_gemfile(project_path('Gemfile')) do
            
            FileUtils.chmod("+x", build_script)
            unless execute(build_script)
              raise error_class, "build script #{build_script} failed"
            end
          end
        end
      end
      default_task :call

      private
      def build_script
        project_path('deploy', 'build')
      end
    end
  end
end

