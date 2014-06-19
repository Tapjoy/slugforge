module Slugforge
  module Commands
    class Jenkins < Slugforge::SubCommand
      class_option :account, :type => :string, :aliases => '-a',
        :desc => 'name of the Github account that owns <repository>.'
      class_option :repository, :type => :string, :aliases => '-r',
        :desc => 'name of the repository to build (defaults to project name)'
      class_option :branch, :type => :string, :aliases => '-b',
        :desc => 'the Git branch to checkout'
      class_option :treeish, :type => :string, :aliases => '-B',
        :desc => "the Git treeish (branch prefixed 'origin/', SHA, or tag) to checkout"
      class_option :ruby, :type => :string, :aliases => '-R',
        :desc => 'MAY NOT BE NECESSARY. USE `.ruby-version` FILE WHENEVER POSSIBLE. This is the ruby version used for the build scripts (not when slug installed).'
      class_option :'jenkins-job', :type => :string, :aliases => '-J',
        :default => 'slug-builder',
        :desc => 'The name of the Jenkins build job for the project'
      class_option :tag, :type => :string, :aliases => '-t',
        :desc => 'once this build is done, tag it with this tag.'
      class_option :'with-git', :type => :boolean,
        :desc => 'Include the .git folder in the slug'
      class_option :qa, :type => :boolean, :hidden => true
      class_option :'slugforge-branch', :type => :string, :hidden => true
      class_option :'fpm-branch', :type => :string, :hidden => true

      desc 'build [ARGS]', 'start a new build of a slug on the Jenkins server'
      option :path, :type => :string, :default => Dir.pwd,
        :desc => 'The path to the local repo of the files being packaged'
      option :nowait, :type => :boolean, :aliases => '-W',
        :desc => 'do not block waiting for Jenkins to finish the build.'
      def build
        additional_options = [] # Array of free-form options
        additional_options << '--with-git' if options[:'with-git']

        params = {}

        params[:account] = account if account
        params[:repo] = repository if repository
        params[:branch] = branch if branch
        params[:tag] = tag if tag
        params[:ruby] = ruby if ruby
        params[:slug_bucket] = config.slug_bucket
        params[:options] = additional_options.join(' ') unless additional_options.empty?
        params[:aws_session_key] = aws_session[:aws_access_key_id]
        params[:aws_session_secret] = aws_session[:aws_secret_access_key]
        params[:aws_session_token] = aws_session[:aws_session_token]

        # Additions to support QA of Slugforge/FPM
        # To test an update to Slugforge and/or FPM, you can add options like:
        #
        # --qa --ruby=1.9.3-p448 --slugforge-branch=2a6b3cc --fpm-branch=master
        #

        params[:qa] = (options[:qa] == true)
        params[:slugforge_branch] = slugforge_branch if slugforge_branch
        params[:fpm_branch] = fpm_branch if fpm_branch

        slug_name = detect_existing_slug(options)
        unless force? || slug_name.nil?
          reuse_slug(slug_name, options)
          return slug_name
        end
        job_id = build_on_jenkins(options, params)
        wait_for_job(job_id, options)
        slug_name_for_job = slug_name_for_job(job_id)
        logger.say_status :slug, slug_name_for_job
        return slug_name_for_job
      end

      desc 'test [ARGS]', 'manually schedules a build of a spec running job for a given project/branch'
      option :'jenkins-job', :type => :string, :default => 'spec_workflow',
        :desc => 'The name of the Jenkins build job for the project'
      option :'parallel_nodes', :type => :string, :default => '1',
        :desc => 'The number of jenkins worker nodes to use when running the specs.'
      option :nowait, :type => :boolean, :aliases => '-W',
        :desc => 'do not block waiting for Jenkins to finish the build.'
      def test
        params = {}
        params[:repo] = "#{account}/#{repository}" if account && repository
        params[:branch] = branch if branch
        params[:parallel_nodes] = parallel_nodes if parallel_nodes

        job_id = build_on_jenkins(options, params)
        wait_for_job(job_id, options)

        return spec_result_for_job(job_id)
      end

      desc 'deploy <hosts...> [ARGS]', 'build a slug on the Jenkins server and deploy it if build succeeded. Blocks until done even if --nowait is specified.'
      option :path, :type => :string, :default => Dir.pwd,
        :desc => 'The path to the local repo of the files being packaged'
      def deploy(*hosts)
        # deploy has to wait for the build to finish
        options[:nowait] = false

        slug_name = build
        if slug_name
          invoke Slugforge::Commands::Deploy, [:name, slug_name, *hosts], ['--project', project_name]
        end
      end

      desc 'list [ARGS]', 'list all or recent builds for a given project'
      option :all, :type => :boolean, :aliases => '-A', :desc => 'list all the builds for a project'
      def list
        show_all, repo = options[:all], (options[:repository] || project_name)
        verify_project_name!(repo)
        build_details = get_builds_by_job_and_repo(options[:'jenkins-job'], repo)
        final_build_details = show_all ? build_details : build_details[0..4]

        if json?
          logger.say_json final_build_details
        else
          final_build_details.each do |detail|
            say_build_status(detail)
          end
        end
      end

      desc 'status <build> [ARGS]', 'lookup the status of a given build on the Jenkins server'
      def status(build)
        status = find_build(build.to_i)
        if json?
          logger.say_json status
        else
          say_build_status status
        end
      end

      private

      def account
        options[:account] || git_account
      end

      def repository
        options[:repository] || project_name
      end

      def branch
        options[:treeish] || ('origin/' << (options[:branch] || git_branch || 'master'))
      end

      def ruby
        options[:ruby]
      end

      def tag
        options[:tag]
      end

      def parallel_nodes
        options[:'parallel_nodes']
      end

      def slugforge_branch
        options[:'slugforge-branch']
      end

      def fpm_branch
        options[:'fpm-branch']
      end

      def detect_existing_slug(opts={})
        remote_sha = git_remote_sha(:memoize => false, :branch => opts[:treeish] || opts[:branch], :url => build_git_url(opts[:account], project_name))
        return nil if remote_sha.nil?
        logger.say_status :detect, "checking for existing slug for SHA #{remote_sha}", :green if verbose?
        find_slug_name(/-#{remote_sha}\.slug$/)
      end

      def reuse_slug(slug_name, opts={})
        logger.say_status :found, "existing slug found for SHA (#{slug_name}); use --force to rebuild slug", :yellow
        if opts[:tag]
          tm = Slugforge::TagManager.new(:s3 => s3, :bucket => aws_bucket)
          tm.create_tag(project_name, opts[:tag], slug_name)
        end
        logger.say_json :status => :success
      end

      def build_on_jenkins (opts={}, params={})
        job_name, job_params = jenkins_build_params(options, params)
        logger.say_status :build, "triggering #{job_name} job build with parameters #{job_params}", :yellow

        try_jenkins_call { jenkins.job.build(job_name, job_params) } unless pretend?

        job_id = get_job_id(job_params[:'build-tag'])
        logger.say_status :build, job_build_url(job_id)

        job_id
      end

      def jenkins_build_params (opts={},params={})

        build_params = []
        build_params << opts[:'jenkins-job']

        # We add build tags to all jobs to give our wait method something to look at
        build_tag = SecureRandom.uuid
        params[:'build-tag'] = build_tag

        build_params << params
        return build_params
      end

      def wait_for_job(job_id, opts={})
        unless opts[:nowait]
          if monitor_job(job_id)
            logger.say_json :job_id => job_id, :status => :success
            logger.say_status :build, "build completed successfully.", :green
          else
            logger.say_json :job_id => job_id, :status => :failed
            logger.say_status :build, "build failed.", :red
            # If the job failed we return nil instead of the job_id that failed
            return nil
          end
        else
          logger.say_json :job_id => job_id, :status => :submitted
          logger.say_status :build, "build request submitted.", :green
        end
      end

      def job_build_url(job_id = nil)
        "#{jenkins_endpoint}/job/#{options[:'jenkins-job']}/#{(job_id.nil? || job_id == 0) ? 'lastBuild' : job_id}/"
      end

      def say_build_status(status)
        logger.say "  "
        status_name = status['building'] ? 'BUILDING' : status['result']
        status_color = { 'SUCCESS' => :green, 'FAILED' => :red }[status_name] || :yellow
        logger.say "Build #{status['number']} ", :blue
        logger.say "#{status_name} ", status_color
        logger.say "#{format_age(Time.at(status['timestamp'].to_i/1000))} ago ", :cyan
        logger.say "- "
        logger.say "#{status['url']}", :magenta
      end
    end
  end
end
