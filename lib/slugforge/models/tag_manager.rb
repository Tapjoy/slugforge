module Slugforge
  class TagManager
    def initialize(opts)
      bucket(opts)
    end

    def bucket(opts={})
      if @bucket.nil? || (true == (opts[:refresh] || @bucket_dirty))
        @s3 = opts[:s3] || @s3
        @aws_bucket = opts[:bucket] || @aws_bucket
        @bucket = @s3.directories.get(@aws_bucket)
        @slugs_for_tag = {}
        @tags = {}
        @bucket_dirty = false
      end
      @bucket
    end

    def projects
      return [] if bucket.files.nil?
      result = {}
      bucket.files.each do |file|
        result[$~[1]] = true if (file.key =~ /^([^\/]+)\//)
      end
      result.keys
    end

    def tags(project_name)
      @tags[project_name] ||= begin
        return [] if bucket.files.nil?
        result = {}
        bucket.files.each do |file|
          result[$~[1]] = true if file.key =~ /^#{project_name}\/tags\/(.+)/
        end
        result.keys
      end
    end

    # This method should be called before iterating over a large set of slugs and
    # calling #tags_for_slug on them. By doing this you are able to query all the
    # data from AWS in advance using parallelized threads, rather than in serial.
    def memoize_slugs_for_tags(project_name)
      @slugs_for_tag[project_name] ||= {}
      tag_map = tags(project_name).parallel_map do |tag|
        next if @slugs_for_tag[project_name][tag]
        file = nil
        begin
          file = bucket.files.get(tag_file_name(project_name, tag))
        rescue Excon::Errors::Forbidden
          # ignore 403's
        end
        slugs = file.nil? ? [] :  file.body.split("\n")
        [tag, slugs]
      end
      tag_map.each do |tag, slugs|
        @slugs_for_tag[project_name][tag] = slugs
      end
    end

    def slugs_for_tag(project_name, tag)
      @slugs_for_tag[project_name] ||= {}
      @slugs_for_tag[project_name][tag] ||= begin
        return [] if bucket.files.nil?
        file = nil
        begin
          file = bucket.files.get(tag_file_name(project_name, tag))
        rescue Excon::Errors::Forbidden
          # ignore 403's
        end
        file.nil? ? [] :  file.body.split("\n")
      end
    end

    def rollback_slug_for_tag(project_name, tag)
      slugs = slugs_for_tag(project_name, tag)
      slugs.shift
      save_tag(project_name, tag, slugs) unless slugs.empty?
      slugs.first
    end

    def slug_for_tag(project_name, tag)
      slugs = slugs_for_tag(project_name, tag)
      slugs.first
    end

    def tags_for_slug(project_name, slug_name)
      tags = tags(project_name)

      tags.select do |tag|
        slug_for_tag(project_name, tag) == slug_name
      end
    end

    def clone_tag(project_name, old_tag, new_tag)
      slugs = slugs_for_tag(project_name, old_tag)
      save_tag(project_name, new_tag, slugs)
    end

    def create_tag(project_name, tag, slug_name)
      slugs = [slug_name]
      slugs += slugs_for_tag(project_name, tag)
      slugs = slugs.slice(0,10)
      save_tag(project_name, tag, slugs)
    end

    def delete_tag(project_name, tag)
      return nil if bucket.files.nil?
      bucket.files.head(tag_file_name(project_name, tag)).destroy
      @bucket_dirty = true
    end

    def save_tag(project_name, tag, slugs)
      bucket.files.create(
        :key    => tag_file_name(project_name, tag),
        :body   => slugs.join("\n"),
        :public => false
      )
      @bucket_dirty = true
    end

    def tag_file_name(project_name, tag)
      [project_name, 'tags', tag].join('/')
    end
  end
end
