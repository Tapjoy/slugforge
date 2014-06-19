module Slugforge
  module Commands
    class Wrangler < Slugforge::SubCommand

      desc 'push <file>', 'push a slug to S3'
      option :tag, :type => :string, :aliases => '-t',
        :desc => 'once pushed tag the slug with this tag.'
      def push(file)
        verify_project_name!
        unless File.exist?(file)
          raise error_class, "file does not exist"
        end

        dest = "#{project_name}/#{file}"
        logger.say_status :upload, "slug #{file} to #{project_name}", :yellow
        s3.put_object(aws_bucket, dest, File.read(file))
        logger.say_status :uploaded, "slug saved"

        if options[:tag]
          logger.say_status :build, "applying tag '#{options[:tag]}' to your fancy new build", :green
          invoke Slugforge::Commands::Tag, [:set, options[:tag], dest], []
        end
      end

      desc 'pull [name_part]', 'pull a slug from S3 (most recent if no name part is specified)'
      def pull(name_part)
        verify_project_name!

        slug = name_part ? find_slug(name_part) : find_latest_slug

        logger.say_status :fetch, "#{slug.attributes[:name]} (#{slug.attributes[:pretty_length]})", :yellow
        logger.say "Note: process will block until download completes."

        # This should block until the body is downloaded.
        # We open the file for writing afterwards to prevent creating empty files.
        slug.body
        File.open(slug.attributes[:name], 'w+') { |f| f.write(slug.body) }

        logger.say_status :fetched, "pull complete, saved to #{slug.attributes[:name]}"
      end

      desc 'list [ARGS]', 'list published slugs for a project'
      option :count, :type => :numeric, :aliases => '-c', :default => 10,
        :desc => 'how many slugs to list'
      option :sort, :type => :string, :aliases => '-s', :default => 'last_modified:desc',
        :desc => 'change the sorting option (field:dir)'
      option :all, :type => :boolean, :aliases => '-a', :default => false,
        :desc => 'list all slugs'
      def list
        raise error_class, "count must be greater than 0" if !options[:all] && options[:count] <= 0

        begin
          project_name = self.project_name
        rescue Thor::Error
          # This is the only case where we don't care if project is not found.
        end

        slugs = (project_name.nil? ? self.files : self.slugs(project_name)).values
        raise error_class, "No slugs found for #{project_name}" if slugs.first.nil?

        total = slugs.length

        sorting   = options[:sort].split(':')
        field     = sorting.first.to_sym
        direction = (sorting.last || 'desc')

        unless slugs.first.class.attributes.include?(field)
          raise error_class, "unknown attribute for sorting: #{field}. Available fields: #{slugs.first.class.attributes * ', '}"
        end

        slugs = slugs.sort_by { |f| f.attributes[field] }
        slugs = slugs.reverse! if direction != 'asc'
        slugs = slugs.slice(0...options[:count]) unless options[:all]

        logger.say "Slugs for #{project_name} (#{slugs.size}", nil, false
        logger.say " of #{total}", nil, false unless options[:all]
        logger.say ")"

        slugs.each do |slug|
          tags = tag_manager.tags_for_slug(project_name, slug.key)
          logger.say " #{tags.size > 0 ? ' (' + tags.join(', ') + ')' : ''} ", :yellow
          logger.say "#{slug.attributes[:name]} ", :green
          logger.say "- "
          logger.say "#{slug.attributes[:pretty_age]} ago ", :cyan
          logger.say "(#{set_color(slug.attributes[:pretty_length], :magenta)})"
        end
      end

      desc 'delete <name_part>', 'delete a slug'
      option :yes, :type => :boolean, :aliases => '-y', :default => false,
        :desc => 'answer "yes" to all questions'
      def delete(name_part)
        slug = find_slug(name_part)
        if options[:yes] || (ask("Are you sure you wish to delete '#{slug.attributes[:name]}'? [yN]").downcase == 'y')
          slug.destroy
          logger.say_status :destroy, slug.key, :red
        else
          logger.say_status :keep, slug.key, :green
        end
      end

      desc 'purge', 'purge slugs for a project'
      option :yes, :type => :boolean, :aliases => '-y', :default => false,
        :desc => 'answer "yes" to all questions'
      option :keep, :type => :numeric, :aliases => '-k', :default => 10,
        :desc => 'number of slugs to keep'
      option :all, :type => :boolean, :aliases => '-a', :default => false,
        :desc => 'purge all slugs'
      def purge
        raise error_class, "keep must be greater than 0" if !options[:all] && options[:keep] <= 0

        slugs = self.slugs(project_name).values

        if options[:all]
          if !options[:yes] && ask("Are you sure you wish to delete #{slugs.size} slugs for #{project_name}? [yN]").downcase == 'y'
            options[:yes] = true
          end

          if options[:yes]
            slugs.each do |slug|
              slug.destroy
              logger.say_status :destroy, slug.key, :red
            end
          end
        elsif slugs.size > options[:keep]
          slugs.slice(options[:keep]..-1).each do |slug|
            if options[:yes] || (ask("Are you sure you wish to delete #{slug.attributes[:name]}? [Yn]").downcase != 'n')
              slug.destroy
              logger.say_status :destroy, slug.key, :red
            else
              logger.say_status :keep, slug.key, :green
            end
          end
        else
          logger.say "Aborting, only #{slugs.size} slugs for #{project_name} and we want to keep #{options[:keep]}"
        end
      end
    end
  end
end

