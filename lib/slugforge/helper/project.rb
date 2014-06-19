module Slugforge
  module Helper
    module Project
      def initialize(args=[], options={}, config={})
        super
        # Tracking the current command so we can be safe when creating projects
        @current_command = config[:current_command]
      end

      protected
      def tag_manager
        @tag_manager ||= TagManager.new(:s3 => s3, :bucket => aws_bucket)
      end

      def bucket
        @bucket ||= s3.directories.get(aws_bucket)
      end

      def project_name
        # First one to return a value wins!
        @project_name ||= config.project || git_repository
        raise error_class, "Could not determine project name. This repository probably doesn't have an upstream branch yet. Please push your code, or specify `--project` when running slugforge." if @project_name.nil?
        @project_name
      end

      def verify_project_name!(project=nil, opts={})
        project ||= project_name
        tm = TagManager.new(:s3 => s3, :bucket => aws_bucket)
        return if tm.projects.include?(project)
        raise error_class, "Project name could not be determined" unless project
      end

      def files
        # If a block is provided, filter the files before mapping them
        files = block_given? ? yield(bucket.files) : bucket.files
        Hash[files.parallel_map_with_index do |file, i|
          key = file.key.split('/', 2)

          file.attributes.merge!({
            :index         => i,
            :name          => key.last,
            :project       => key.first,
            :age           => (Time.now.to_f - file.last_modified.to_f),
            :pretty_age    => format_age(file.last_modified),
            :pretty_length => format_size(file.content_length)
          })

          [file.key, file]
        end]
      end

      def slugs(project)
        filter = Proc.new do |files|
          result=[]
          # Fog only #maps against the first 1000 items, so we will use #each instead
          files.each { |file| result << file if file.key =~ /^#{project}\/.*\.slug$/ } # ex match: project/blag.slug
          result
        end
        files(&filter)
      end

      def find_latest_slug
        self.slugs(project_name).values.sort_by { |s| s.last_modified }.last
      end

      # finds a slug with name_part somewhere in the name. Use enough of the name to make
      # it unique or this will just return the first slug it finds
      def find_slug(name_part)
        s = self.slugs(project_name).values.find_all { |f| f.attributes[:key].include?(name_part) }
        if s.size == 0
          raise error_class, "unable to find a slug from '#{name_part}'. Use 'wrangler list' command to see available slugs"
        elsif s.size > 1
          raise error_class, "ambiguous slug name. Found more than one slug with '#{name_part}' in their names.\n#{s.map{|sl| File.basename(sl.key)} * "\n"}\n Use 'wrangler list' command to see available slugs"
        end
        s[0]
      end

      def find_slug_name(pattern)
        slugs = self.slugs(project_name).values.select { |f| f.attributes[:key] =~ pattern }
        return nil if slugs.empty?
        slugs.sort_by { |s| s.last_modified }.last.key
      end
    end
  end
end

