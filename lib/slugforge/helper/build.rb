module Slugforge
  module Helper
    module Build
      def verify_procfile_exists!
        unless File.exist?(project_path('Procfile'))
          logger.say_status :warning, "Slugforge should normally be run in a project with a Procfile (#{project_path('Procfile')})", :yellow
        end
      end

      def ruby_version_specified?
        options[:ruby] and !options[:ruby].empty?
      end

      def has_ruby_version_file?
        File.exist?(project_path('.ruby-version'))
      end

      def get_ruby_version_from_file
        ruby_version = read_from_file
        if ruby_version.nil? or ruby_version.empty?
          raise error_class, "You don't have a ruby version specified in your .ruby-version file!!! Why you no set ruby version."
        else
          return ruby_version
        end
      end

      def read_from_file
        begin
          File.read(project_path('.ruby-version')).delete("\n")
        rescue Exception => e
          raise error_class, "There were issues reading the .ruby-version file. Make sure it exists in the project path and it has valid content, #{e}."
        end
      end

      def package_file_name
        "#{project_name}-#{date_stamp}-#{git_sha}.slug"
      end

      def date_stamp
        # Keep this as a class variable so the date stamp remains the same throughought the lifecycle of the app.
        @@date_stamp ||= Time.now.strftime('%Y%m%d%H%M%S')
      end
    end
  end
end

