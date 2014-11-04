require 'slugforge/models/host'
require 'slugforge/models/host_group'

module Slugforge
  module Commands
    class Deploy < Slugforge::SubCommand
      class_option :identity, :type => :string, :aliases => '-i',
        :desc => 'The identify (.pem) file to use for authentication'
      class_option :deploy_dir, :type => :string, :aliases => '-d',
        :desc => 'The directory to deploy to on the server'
      class_option :owner, :type => :string, :aliases => '-o',
        :desc => 'Account that the application will run with when deployed'
      class_option :env, :type => :string, :aliases => '-e',
        :desc => 'A quoted, space-delimited list of environment variables and values'
      class_option :count, :type => :numeric, :aliases => '-c',
        :desc => 'Only deploy to the specified number hosts in the expanded list'
      class_option :percent, :type => :numeric,
        :desc => 'Only deploy to the specified percent in the expanded list'
      # AWS may throttle simultaneous downloads to a file
      class_option :'batch-size', :type => :numeric, :default => 85,
        :desc => 'Set the number of hosts per deployment batch to help slow your roll'
      class_option :'batch-count', :type => :numeric,
        :desc => 'Set the number of deployment batches to help slow your roll'
      class_option :'batch-pause', :type => :numeric,
        :desc => 'Set the amount of time (in seconds) to pause between deployment batches, to further slow your roll'
      class_option :'no-stage', :type => :boolean, :default => false,
        :desc => "Don't stage the slug files on the host group members that were not targeted for the deploy"
      class_option :'yes', :type => :boolean, :default => false,
        :desc => "Do not prompt to proceed with deploy (a more gentle --force)"

      desc 'file <filename> <hosts...> [ARGS]', 'deploy a slug file to host(s)'
      option :path, :copy_type => :string, :default => Dir.pwd,
        :desc => 'The path to the files being packaged'
      def file(filename, *hosts)
        logger.say_status :deploy, "deploying local slug #{filename}", :green
        slug_name = File.basename(filename)

        deploy(hosts, slug_name, deploy_options(:copy_type => :scp, :filename => filename))
      end

      desc 'name <name_part> <hosts...> [ARGS]', 'deploy an S3 stored slug by name to host(s) (use `wrangler list` for slug names)'
      def name(name_part, *hosts)
        slug = find_slug(name_part)
        slug_name = File.basename(slug.key)
        logger.say_status :deploy, "deploying slug #{slug_name} from s3", :green

        url = expiring_url(slug)
        deploy(hosts, slug_name, deploy_options(:copy_type => :aws_cmd, :url => url, :aws_session => aws_session, :s3_url => "s3://#{aws_bucket}/#{slug.key}"))
      end

      desc 'rollback <tag> <hosts...> [ARGS]', 'deploy the previous slug for a tag to host(s)'
      def rollback(tag, *hosts)
        raise error_class, "There is no project found named '#{project_name}'. Try setting the project name with --project" unless tag_manager.projects.include?(project_name)
        data = tag_manager.rollback_slug_for_tag(project_name, tag)
        if data.nil?
          raise error_class, "could not find tag '#{tag}' for project '#{project_name}'"
        else
          logger.say_status :deploy, "deploying slug #{data}", :green
          slug = find_slug(data)
          slug_name = File.basename(data)
          url = expiring_url(slug)
        end

        raise error_class, "could not determine URL for tag" unless url
        deploy(hosts, slug_name, deploy_options(:copy_type => :aws_cmd, :url => url, :aws_session => aws_session, :s3_url => "s3://#{aws_bucket}/#{data}"))
      end

      desc 'tag <tag> <hosts...> [ARGS]', 'deploy a slug by tag to host(s)'
      def tag(tag, *hosts)
        raise error_class, "There is no project found named '#{project_name}'. Try setting the project name with --project" unless tag_manager.projects.include?(project_name)
        data = tag_manager.slug_for_tag(project_name, tag)
        if data.nil?
          raise error_class, "could not find tag '#{tag}' for project '#{project_name}'"
        else
          logger.say_status :deploy, "deploying slug #{data}", :green
          slug = find_slug(data)
          slug_name = File.basename(data)
          url = expiring_url(slug)
        end

        raise error_class, "could not determine URL for tag" unless url

        deploy(hosts, slug_name, deploy_options(:copy_type => :aws_cmd, :url => url, :aws_session => aws_session, :s3_url => "s3://#{aws_bucket}/#{data}"))
      end

      desc 'ssh <hosts...> [ARGS]', 'log in to a box for testing', :hide => true
      def ssh(*hosts)
        deploy hosts, nil, deploy_options(:copy_type => :ssh)
      end

      private
      def deploy_options(opts={})
        {
          :username   => config.ssh_username,
          :deploy_dir => options[:deploy_dir] || self.deploy_dir,
          :owner      => options[:owner],
          :identity   => options[:identity],
          :env        => options[:env],
          :force      => force?,
          :pretend    => pretend?,
          :verbose    => verbose?
        }.merge(opts)
      end

      def deploy(host_patterns, slug_name, deploy_opts)
        host_groups = determine_host_groups(host_patterns)
        return unless confirm_deployment_start?(host_groups)

        # Stage file on all other hosts in facets, unless told otherwise
        unless options[:'no-stage']
          host_groups.each do |group|
            group.hosts.each { |host| host.add_action(:stage) unless host.install? }
          end
        end

        logger.say_status :deploy, "beginning deployment", :green

        # Organize the list of hosts to more evenly spread load across impacted facets
        hosts = order_deploy(unique_hosts(host_groups))
        batches = (batch_size(hosts.count) == 0) ? [hosts] : hosts.each_slice(batch_size(hosts.count)).to_a

        partial_deploy_type = [:count, :percent].detect{ |s| options[s] }

        publish('deploy.started', {
          :partial_deploy_method => partial_deploy_type,
          :partial_deploy_limit  => options[partial_deploy_type],
          :host_groups           => host_groups,
          :batch_size            => batch_size(hosts.count),
          :project               => project_name,
          :slug_name             => slug_name
        })

        deploy_in_batches(batches, slug_name, deploy_opts)

        logger.say_status :deploy, "deployment complete!", :green
        say_deploy_status(host_groups, slug_name)


        publish('deploy.finished', {
          :success               => hosts.all?(&:success?),
          :partial_deploy_method => partial_deploy_type,
          :partial_deploy_limit  => options[:count] || options[:percent],
          :host_groups           => host_groups,
          :batch_size            => batch_size(hosts.count),
          :project               => project_name,
          :slug_name             => slug_name
        })

        host_groups
      end

      def deploy_in_batches(batches, slug_name, deploy_opts)
        pause = options[:'batch-pause'].to_i
        batches.each.with_index(1) do |batch, i|
          logger.say "deploying batch #{i} of #{batches.count}", :magenta if batches.count > 1
          threads = {}
          batch.each do |host|
            thread = Thread.new do
              host.deploy(slug_name, logger, deploy_opts)
            end
            threads[host.ip] = thread
          end
          join_batch_threads(threads, batch, logger)
          unless (batches.length == i || pause == 0)
            logger.say "batch #{i} complete; pausing for #{pause} seconds", :magenta
            sleep pause
          end
        end
      end

      def say_deploy_status(host_groups, slug_name)
        return nil if host_groups.nil?
        hosts = unique_hosts(host_groups)
        return nil if hosts.empty?
        total_count = hosts.count
        successful = hosts.select { |h| h.success? }.count
        overall_success = (total_count == successful)

        if json?
          logger.say_json :hosts => hosts.map(&:to_status), :success => overall_success
        else
          status_color = overall_success ? :green : :red
          logger.say "\n#{'-'*22}\n| Deployment Summary |\n#{'-'*22}", status_color
          logger.say "Deployed #{slug_name} to "
          logger.say "#{successful} ", status_color
          logger.say "of "
          logger.say "#{total_count} ", status_color
          logger.say "hosts in "
          logger.say "#{elapsed_time}", :yellow

          unless overall_success
            indent = Math.log10(total_count - successful).round + 4
            logger.say "\nFailures:", :red
            count = 0
            hosts.each do |host|
              unless host.success?
                logger.say ""
                logger.say "%#{indent}s" % "#{count += 1}) ", :red
                logger.say "#{host.name}", :red
                print_wrapped host.output.join("\n"), :indent => indent
              end
            end
          end
          log_rollout_status(host_groups)
        end
      end

      def determine_host_groups(host_patterns)
        say_option_status host_patterns
        logger.say_status :deploy, "determining deployment targets", :green
        host_groups = partial_install_groups(host_groups_for_patterns(host_patterns))
      end

      def confirm_deployment_start?(host_groups)
        say_predeploy_status(host_groups)
        if !(force? || json? || options[:yes]) && (ask("Are you sure you wish to deploy? [yN]").downcase != 'y')
          logger.say_status :deploy, "deployment aborted!", :red
          return false
        end
        # Reset the start time for more useful reporting
        @command_start_time = Time.now()
        true
      end

      def unique_hosts(host_groups)
        # If we're not staging the slug, return just the hosts being installed to
        options[:'no-stage'] ? host_groups.collect {|host_group| host_group.hosts_for_action(:install)}.flatten.uniq { |h| h.name } : host_groups.map(&:hosts).flatten.uniq { |h| h.name }
      end

      def order_deploy(hosts)
        # Percolate installations to the top, then stripe across batches
        hosts.sort! {|a,b| a.install? ? -1 : 1}
        results=[]
        batches = hosts.count / batch_size(hosts.count)
        hosts.each.with_index {|item, index| results[index % batches].nil? ? results[index % batches] = [item] : results[index % batches] << item }
        results.flatten
      end

      def join_batch_threads(threads, hosts, logger)
        joined = false
        while !joined
          begin
            threads.map { |ip,thread| thread }.map(&:join)
            joined = true
          rescue Interrupt  # Ctrl+C
            logger.say "\nWe are #{elapsed_time} in. Stragglers for this batch:", :magenta
            hosts.reject { |host| host.complete? }.each_with_index do |host, stripe|
              logger.say "  #{host.name} (Timeline: #{host.timeline})", stripe.odd? ? :cyan : :yellow
            end
            logger.say "Maybe you should give 'em them the clamps?", :magenta
            case ask("(T)erminate stragglers, (F)ail stragglers, (?) for help, or anything else to keep waiting:").downcase
            when 'f'
              break
            when 't'
              logger.say "Gee, you think? You think that maybe I should use these clamps that I use every day at every opportunity? You're a freakin' genius, you idiot!", :magenta
              hosts.each_with_index do |host, index|
                next if host.complete?
                if host.id.nil? || !host.is_autoscaled?
                  logger.say "Can't terminate #{host.name} as it is not part of an autoscaler"
                else
                  logger.say "Terminating #{host.name} (#{['Clamp.','Clamp!','Clampity Clamp!'][index%3]})", index.odd? ? :cyan : :yellow
                  threads[host.ip].terminate
                  host.record_event(:terminated)
                  autoscaling.terminate_instance_in_auto_scaling_group(host.id, false)
                end
              end
            when '?'
              straggler_help
            end
          end
        end
      end

      def straggler_help
        logger.say <<-EOF

T) Attempt to terminate the stragglers and let their autoscaling group create new instances. The deploy will end if everyone who had not completed could be terminated.
F) Mark the remaining stragglers are failed and end the deployment
?) Display this help and resume the deploy
EOF
      end

      def say_option_status(host_patterns)
        subset_name = if options[:count]
          "#{options[:count]} server#{(options[:count] == 1) ? '' : 's'}"
        elsif options[:percent]
          "#{options[:percent]}% of servers"
        else
          "all servers"
        end
        logger.say_status :deploy, "targeting #{subset_name} for: #{host_patterns.join(', ')}", :green
      end

      def say_predeploy_status(host_groups)
        total_count = host_groups.inject(0) { |sum, host_group| sum += host_group.hosts.count }
        install_count = 0
        host_groups.each_with_index do |host_group, stripe|
          raise error_class, "Host group #{host_group.name} was empty!" if host_group.hosts.nil?
          install_hosts = host_group.hosts_for_action(:install)
          install_count += install_hosts.count
          install_hosts.each do |host|
            unless json?
              logger.say  # Add a newline for cleaner paste into Flowdock
              logger.say "#{host_group.name}: ", stripe.odd? ? :cyan : :yellow
              logger.say "#{host.name}"
            end
          end
        end
        logger.say  # Add a newline for cleaner paste into Flowdock
        logger.say_status :deploy, "#{with_units(install_count, 'host')} targeted for installation out of #{with_units(total_count, 'host')} total", :green

        batch_host_count = options[:'no-stage'] ? host_groups.inject(0) { |sum, host_group| sum += host_group.hosts_for_action(:install).count } : total_count
        batches = (batch_host_count/batch_size(batch_host_count).to_f).ceil
        logger.say_status :deploy, "using #{batches} batch#{batches == 1 ? '' : 'es'} of #{with_units(batch_size(batch_host_count), 'host')} for installation #{options[:'no-stage'] ? '' : 'and staging'} ", :green
      end

      def with_units(value, unit)
        "#{value} #{unit}#{(value == 1) ? '' : 's'}"
      end

      def log_rollout_status(host_groups)
        return if host_groups.nil?
        result = { :environment => overall_status, :hostgroups => [] }
        host_groups.each do |host_group|
          host_group.hosts.each do |host|
            result[:hostgroups] << { :group => host_group.name }.merge(host.to_status)
          end
        end
        filename = "slugforge_status-#{date_stamp}.json"
        logger.say "Writing full status report to #{filename}"
        File.open(filename, "w") do |f|
          f.write(JSON.pretty_generate(result))
        end
        purge_old_files 'slugforge_status-*.json'
      end

      def overall_status
        {
          :command_line   => "#{$0} #{$*.join(' ')}",
          :options        => @options,
          :ruby_version   => RUBY_VERSION,
          :ec2_access_key => @ec2_access_key,
          :s3_access_key  => @s3_access_key,
          :git_info       => git_info,
        }
      end

      def purge_old_files(file_mask, keep_count = 10)
        old_files = Dir.glob(file_mask).sort_by{ |f| File.ctime(f) }.reverse.slice(keep_count..-1)
        File.delete(*old_files)
      end

      def host_groups_for_patterns(host_patterns)
        host_groups = HostGroup.discover(host_patterns, compute)
        raise error_class, "Unable to determine what host or group of hosts you meant with '#{pattern}'." unless host_groups
        # determine unique hosts in each list, then sort by IP (alphabetically) to make partial deploys essentially deterministic
        host_groups
      end

      def partial_install_groups(host_groups)
        if options[:percent]
          return host_groups.each { |host_group| host_group.install_percent_of_hosts(options[:percent]) }
        elsif options[:count]
          return host_groups.each { |host_group| host_group.install_number_of_hosts(options[:count]) }
        end
        host_groups.each { |host_group| host_group.install_all }
      end

      private
      def batch_size(host_count = 1)
        if options[:'batch-count'] && host_count >= options[:'batch-count'].to_i
          batch_count = options[:'batch-count'] < 1 ? 1 : options[:'batch-count']
          (host_count / batch_count.to_f).ceil
        elsif options[:'batch-size'] && host_count > options[:'batch-size'].to_i
          batch_size = options[:'batch-size'].to_i
          batch_size = batch_size < 1 ? host_count : batch_size
        else
          host_count > 1 ? host_count : 1
        end
      end
    end
  end
end

