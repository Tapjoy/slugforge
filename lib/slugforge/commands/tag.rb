require 'parallel'

module Slugforge
  module Commands
    class Tag < Slugforge::SubCommand
      desc 'clone <tag> <new_tag> [ARGS]', 'create a new tag with the same slug as an existing tag'
      def clone(tag, new_tag)
        verify_project_name!

        slug_name = tag_manager.slug_for_tag(project_name, tag)
        unless slug_name.nil?
          tag_manager.clone_tag(project_name, tag, new_tag)
          logger.say_json :project => project_name, :tag => new_tag, :slug => slug_name
          logger.say_status :set, "#{project_name} #{new_tag} to Slug #{slug_name}"
          true
        else
          logger.say_json :tag => tag, :exists => false
          logger.say_status :clone, "could not find existing tag #{tag} for project '#{project_name}'", :red
          false
        end
      end

      desc 'delete <tag> [ARGS]', 'delete a tag'
      option :yes, :type => :boolean, :aliases => '-y', :default => false,
        :desc => 'answer "yes" to all questions'
      def delete(tag)
        verify_project_name!

        status = if tag_manager.tag_exists?(project_name, tag)
                   if options[:yes] || json? || (ask("Are you sure you wish to delete tag '#{tag}'? [Yn]").downcase != 'n')
                     tag_manager.delete_tag(project_name, tag)
                     :deleted
                   else
                     :kept
                   end
                 else
                   :not_found
                 end
        logger.say_status status, "#{project_name} #{tag}"
        logger.say_json :status => status, :tag => tag, :project_name => project_name
      end

      desc 'history <tag> [ARGS]', 'show history of a project\'s tag'
      def history(tag)
        verify_project_name!

        slug_names = tag_manager.slugs_for_tag(project_name, tag)
        unless slug_names.empty?
          logger.say_json :project => project_name, :tag => tag, :slug_names => slug_names, :exists => true
          slug_names.each.with_index(0) do |slug_name, index|
            logger.say_status (index == 0 ? 'current' : "-#{index}"), slug_name, :yellow
          end
        else
          logger.say_json :tag => tag, :exists => false
        end
      end

      desc 'list [ARGS]', 'list a project\'s tags'
      def list
        verify_project_name!

        tags = tag_manager.tags(project_name)
        pc = tags.delete('production-current')

        if json?
          logger.say_json tags
        else
          logger.say "Tags for #{project_name}"
          logger.say_status :'production-current', tag_manager.slug_for_tag(project_name, 'production-current') unless pc.nil?

          tag_list = Parallel.map(tags) do |tag|
            [tag, tag_manager.slug_for_tag(project_name, tag)]
          end
          tag_list.sort {|a,b| b[1].to_s<=>a[1].to_s }.each do |tag, slug|
            logger.say_status tag, slug, :yellow
          end
        end
      end

      desc 'migrate', 'migrate tags to new format', :hide => true
      def migrate
        metadata = JSON.parse(bucket.files.get('projects.json').body)
        metadata.each do |project, data|
          data['tags'].each do |tag, value|
            puts "create_tag(#{project}, #{tag}, #{value['s3']})"
            tag_manager.create_tag(project, tag, value['s3'])
          end
        end
      end

      desc 'purge [ARGS]', 'delete tags that point to missing slugs (excluding production-current)'
      def purge
        verify_project_name!

        tags = tag_manager.tags(project_name)
        tags.delete('production-current')

        bucket  # initialize value before using threads
        logger.say_status :purge, "Reviewing #{tags.count} tags for #{project_name}", :cyan
        results = Parallel.map(tags) do |tag|
          begin
            slug_file = tag_manager.slug_for_tag(project_name, tag)
            if !slug_file.nil? && bucket.files.head(slug_file)
              logger.say '+', :green, false
              [tag, :valid]
            else
              if pretend?
                logger.say '.', :magenta, false
                [tag, :pretend]
              else
                tag_manager.delete_tag(project_name, tag)
                logger.say '-', :red, false
                [tag, :deleted]
              end
            end
          rescue Excon::Errors::Forbidden
            logger.say '?', :yellow, false
            [tag, :forbidden]
          end
        end.sort {|a,b| a[1].to_s <=> b[1].to_s}

        logger.say
        results.each do |result|
          tag, status = result
          next if status == :valid
          logger.say_status status, tag, (status == :deleted) ? :red : :yellow
        end
      end

      desc 'show <tag> [ARGS]', 'show value of a project\'s tag'
      def show(tag)
        verify_project_name!

        slug_name = tag_manager.slug_for_tag(project_name, tag)
        unless slug_name.nil?
          exists = !bucket.files.head(slug_name).nil?
          logger.say_json :project => project_name, :tag => tag, :slug_name => slug_name, :exists => exists
          logger.say_status tag, "#{slug_name} (#{exists ? "exists" : "missing"})", :yellow
        else
          logger.say_json :tag => tag, :exists => false
        end
      end

      desc 'set <tag> <name_part>', 'update a tag to point to a slug in s3'
      def set(tag, name_part)
        verify_project_name!

        slug = find_slug(name_part)

        tag_manager.create_tag(project_name, tag, slug.key)
        logger.say_json :project => project_name, :tag => tag, :slug => slug.key
        logger.say_status :set, "#{project_name} #{tag} to Slug #{slug.key}"
      end
    end
  end
end

