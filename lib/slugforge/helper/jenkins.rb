require 'jenkins_api_client'

module Slugforge
  module Helper
    module Jenkins

      DETAILS_ABOUT_BUILDS = %w(number url timestamp result)
      MAX_TRIES = 15

      def jenkins
        @jenkins ||= JenkinsApi::Client.new(jenkins_api_params)
      end

      def get_builds_by_job_and_repo(job_name, repo_name)
        builds = find_builds_for_job(job_name)
        final_build_details = builds.collect do |build|
          details = try_jenkins_call{jenkins.job.get_build_details(job_name, build['number'])}
          next unless build_associated_with_repo?(details, repo_name)
          details.select { |k,v| DETAILS_ABOUT_BUILDS.include?(k) }
        end
        final_build_details.compact
      end

      private
      def jenkins_api_params
        {
          :server_url => jenkins_endpoint,
          :log_level  => ::Logger::FATAL,
          :username   => jenkins_username,
          :password   => jenkins_token
        }.reject { |k,v| v.nil? }
      end

      def jenkins_endpoint
        @jenkins_endpoint ||= config.jenkins_endpoint
        verify_jenkins_config @jenkins_endpoint, 'endpoint'
      end

      def jenkins_username
        @jenkins_username ||= config.jenkins_username
        verify_jenkins_config @jenkins_username, 'username'
      end

      def jenkins_token
        @jenkins_token ||= config.jenkins_token
        verify_jenkins_config @jenkins_token, 'token'
      end

      def jenkins_job_name
        @jenkins_job_name = options[:'jenkins-job'] || project_name
      end

      # It is not uncommon for jenkins to not respond to an API call resulting in client errors. Retrying
      # is usually the right thing and this keeps users (like deployboard) from failing on temporary problems.
      def try_jenkins_call
        tries = 0
        begin
          yield
        rescue EOFError,SocketError,Timeout::Error => e
          tries += 1
          if tries > MAX_TRIES
            raise error_class "Something is wrong with jenkins. We tried but were unable to get a response. Exiting: #{e}"
          else
            logger.say_status :retrying, "We had a problem communicating with jenkins, trying again. Attempt #{tries}/#{MAX_TRIES}: #{e}", :yellow
            sleep 2
            retry
          end
        end
      end

      def job_details(opts={})
        memoize = opts[:memoize] || true
        return @job_details if (@job_details && memoize)
        @job_details = try_jenkins_call { jenkins.job.list_details(jenkins_job_name) }
      end

      def get_job_id_for_tag_from_details(tag, details, max_depth)
        ids = details['builds'][0..max_depth].map do |build|
          begin
            build_info = find_build(build['number'], :memoize => true)
          rescue Thor::Error
            # build is no longer available on Jenkins
            return nil
          end
          found = build_info['actions'].detect do |action|
            action['parameters'].detect do |params|
              (params['name'] == 'build-tag' && params['value'] == tag) ? build['number'] : nil
            end if action && action['parameters']
          end
          build['number'] if found
        end
        ids ? ids.compact.first : 0
      end

      def verify_jenkins_config(variable, message)
        raise error_class, "Jenkins #{message} is required to access Jenkins" unless variable
        variable
      end

      def find_build(number, opts={})
        memoize = opts[:memoize] || false
        return pretend_build_details if pretend?
        begin
          @build_details ||= []
          return @build_details[number] if @build_details[number] && memoize
          @build_details[number] = (try_jenkins_call {jenkins.job.get_build_details(jenkins_job_name, number)} if job_details)
        rescue JenkinsApi::Exceptions::NotFound => e
          raise error_class, "We couldn't find the build on the jenkins server. Please verify the project name and that the build hasn't been purged. (#{jenkins_job_name} ##{number}) #{e}"
        end
      end

      def pretend_build_details
        details = {
          'result' => 'SUCCESS',
          'artifacts' => [
            'fileName' => 'artifact.slug'
          ]
        }
      end

      def get_job_id(build_tag)
        return @job_id if @job_id
        logger.say_status :build, "waiting for Jenkins to assign job number (press Ctrl-C to stop waiting)"
        return 1 if pretend?
        job_id = nil
        max_depth = 1
        begin
          tries = 0
          while !job_id && tries < MAX_TRIES
            tries += 1
            sleep 2
            max_depth <<= 1 unless max_depth > 1000
            job_id = get_job_id_for_tag_from_details(build_tag, job_details(:memoize => false), max_depth)
          end
        rescue Interrupt
          logger.say ' stopping waiting at user request'
        end
        @job_id = job_id || 0
      end

      def monitor_job(job_id)
        return false unless job_id && job_id > 0
        logger.say_status :waiting, "monitoring status of job #{job_id} (press Ctrl-C to stop)"
        return true if pretend?
        begin
          if verbose?
            monitor_console_output(job_id)
          else
            monitor_simple_status(job_id)
          end
        rescue Interrupt
          logger.say ' stopping at user request'
        end

        status = find_build(job_id)['result']
        if status == 'UNSTABLE' && force?
          return true
        end
        status == 'SUCCESS'
      end

      def monitor_console_output(job_id)
        response = try_jenkins_call {jenkins.job.get_console_output(jenkins_job_name, job_id)}
        while response['more']
          logger.say response['output'], :clear unless response['output'].chomp.empty?
          response = try_jenkins_call {jenkins.job.get_console_output(jenkins_job_name, job_id, response['size'])}
        end

        if json?
          return response['output']
        else
          logger.say response['output'], :clear
        end
      end

      def monitor_simple_status(job_id)
        build_status = find_build(job_id)
        old_result = build_status['result']
        while build_status['building']
          sleep 3
          build_status = find_build(job_id)
          new_result = build_status['result']
          next if new_result == old_result
          logger.say_status :waiting, "job status has changed to #{new_result}"
          old_result = new_result
          break if ['FAILURE', 'ABORTED'].include?(old_result)
        end
        return old_result == 'SUCCESS'
      end

      def find_builds_for_job(job_name)
        begin
          try_jenkins_call{jenkins.job.get_builds(job_name)}
        rescue JenkinsApi::Exceptions::NotFound => e
          raise error_class, "#{e} (#{job_name} builds not found)"
        end
      end

      def build_associated_with_repo?(details, repo_name)
        begin
          details['actions'].first['parameters'].any? { |param| param['name'] == 'repo' and param['value'] == repo_name }
        rescue NoMethodError
          false
        end
      end

      def slug_name_for_job(job_id)
        details = find_build(job_id)
        assets = details['artifacts'].map do |artifact|
          artifact['fileName'] if artifact['fileName'] =~ /\.slug$/
        end.compact.first
      end

      def spec_result_for_job(job_id)
        details = find_build(job_id)
        result = details['result']

        if json? && options[:nowait].nil?
          spec_result = {}
          spec_result['result'] = find_build(job_id)['result']
          spec_result['console_output'] = monitor_console_output(job_id)
          logger.say_json spec_result
        elsif options[:nowait]
          return
        else
          message = "Spec Job Result: #{result}"
          response = try_jenkins_call {jenkins.job.get_console_output(jenkins_job_name, job_id)}
          console_output = response['output']
          result == 'SUCCESS' ? logger.say(message) : logger.say(message << "\n\n Console Output: \n\n#{console_output}")
        end
      end
    end
  end
end

