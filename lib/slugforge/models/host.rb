require 'net/ssh'
require 'net/scp'

module Slugforge
  class Host
    attr_reader :pattern, :server, :slug_name, :status

    def initialize(pattern, server=nil)
      @pattern = pattern
      @server  = server
      @deploy_results  = []
      @timeline = []
      @start_time = Time.now
      @actions = []
      self
    end

    def name
      "name:#{@pattern}"
    end

    def ip
      @pattern
    end

    def ssh_host
      @pattern
    end

    def id
      nil
    end

    def is_autoscaled?
      false
    end

    def to_status
      {
        :name       => name,
        :ip         => ip,
        :pattern    => @pattern,
        :slug_name  => @slug_name,
        :action     => effective_action.to_s,
        :status     => @status.to_s,
        :output     => @deploy_results,
        :start_time => @start_time,
        :timeline   => timeline,
      }
    end

    def elapsed_time
      Time.at(Time.now - @start_time).strftime('%M:%S')
    end

    def record_event(status)
      @status = status
      @timeline << {:status => status, :elapsed_time => elapsed_time}
    end

    def timeline
      @timeline.map { |event| "#{event[:status]} @ #{event[:elapsed_time]}" }.join ', '
    end

    def complete?
      success? || failed?
    end

    def success?
      # Only actual install requests should count; don't count staging only, etc.
      return true unless install?
      # TODO: Add support for considering partial failures as 'success'

      # A clean install is absolutely a success; anything else is a failure at this point
      [:deployed, :terminated].include?(status) && output.empty?
    end

    def failed?
      @status == :failed
    end

    def add_action(action)
      @actions << action
    end

    def has_action?(action)
      @actions.include?(action)
    end

    def remove_action(action)
      @actions.delete(action)
    end

    def stage?
      @actions.include?(:stage)
    end

    def install?
      @actions.include?(:install)
    end

    def effective_action
      return :install if @actions.include?(:install)
      :stage
    end

    def terminated?
      @status == :terminated
    end

    def output
      @deploy_results.map { |result| result[:output] unless result[:exit_code] == 0 }.compact
    end

    def deploy(slug_name, logger, opts)
      begin
        record_event :started
        if opts[:pretend]
          logger.log "not actually #{effective_action} slug (#{name})", {:color => :yellow, :status => :pretend}
        else
          logger.say_status effective_action, "#{name} as #{username(opts)}", (effective_action == :install) ? :green : :yellow
          Net::SSH.start(ssh_host, username(opts), ssh_opts(opts)) do |ssh|
            host_slug = detect_slug(ssh, slug_name, logger) unless opts[:force]
            host_slug ||= copy_slug(ssh, slug_name, logger, opts)
            explode_slug(ssh, host_slug, logger, opts) if stage?
            install_slug(ssh, host_slug, logger, opts) if install?
          end
        end
        record_event :deployed
      rescue => e
        record_event :failed
        message = "#{e.class.to_s}: #{e.to_s}"
        logger.log "#{message} (#{ip}: #{name})", {:color => :red, :status => :fail}
        @deploy_results << {:output => message}
      end
      logger.say_status :deploy, "#{effective_action} complete for host: #{name}", success? ? :green : :red
      @deploy_results
    end

    private
    def ssh_opts(opts = {})
      ssh_opts = { :forward_agent => true }
      if opts[:identity]
        ssh_opts[:key_data] = File.read(opts[:identity])
        ssh_opts[:keys_only] = true
      end
      ssh_opts
    end

    def detect_slug(ssh, slug_name, logger)
      found_path = ['/tmp', '/mnt'].select do |path|
        file_count(ssh, path, slug_name) > 0
      end.compact
      return nil if found_path.empty?
      slug_name_with_path = "#{found_path.first}/#{slug_name}"
      logger.log "found existing slug (#{slug_name_with_path}) on host (#{name}); use --force to overwrite slug", {:color => :yellow, :status => :detect, :log_level => :vervose}
      record_event :detected
      slug_name_with_path
    end

    def copy_slug(ssh, slug_name, logger, opts)
      slug_name_with_path = "/mnt/#{slug_name}"
      case opts[:copy_type]
      when :ssh
        logger.log "interactive mode enabled (be sure to set slug_name)", {:color => :yellow, :status => :copy, :log_level => :verbose}
        binding.pry
      when :scp
        logger.log "copying slug to host via SCP (#{name})", {:color => :green, :status => :copy, :log_level => :verbose}
        scp_upload ip, username(opts), opts[:filename], "#{slug_name}", logger, :ssh => ssh_opts
        logger.log "moving slug from ~ to /mnt as root", {:color => :green, :status => :copy, :log_level => :verbose}
        ssh_command(ssh, "sudo mv #{slug_name} #{slug_name_with_path}", logger)
      else # AWS S3 command line by default
        logger.log "copying slug to host via aws s3 command (#{name})", {:color => :green, :status => :copy, :log_level => :verbose}
        ssh_command(ssh, "sudo -- sh -c 'export AWS_ACCESS_KEY_ID=#{opts[:aws_session][:aws_access_key_id]}; export AWS_SECRET_ACCESS_KEY=#{opts[:aws_session][:aws_secret_access_key]}; export AWS_SECURITY_TOKEN=#{opts[:aws_session][:aws_session_token]}; export AWS_DEFAULT_REGION=#{opts[:aws_session][:aws_region]}; aws s3 cp #{opts[:s3_url]} #{slug_name_with_path} #{s3_cp_opts(opts)}'", logger)
      end
      record_event :copied
      slug_name_with_path
    end

    def s3_cp_opts(opts)
      '--quiet' unless opts[:verbose]
    end

    def username(opts)
      opts[:username] || Net::SSH.configuration_for(ip)[:user] || `whoami`.chomp
    end

    def explode_slug(ssh, slug_name_with_path, logger, opts)
      logger.log "exploding package as root #{"for user " + opts[:owner] if opts[:owner]}", {:color => :green, :status => :stage, :log_level => :verbose}
      ssh_command(ssh, slug_install_command(slug_name_with_path, opts[:deploy_dir], {:unpack => true, :owner => opts[:owner], :env => opts[:env]}), logger)
      @slug_name = slug_name
    end

    def install_slug(ssh, slug_name_with_path, logger, opts)
      logger.log "installing package as root #{"for user " + opts[:owner] if opts[:owner]}", {:color => :green, :status => :install, :log_level => :verbose}
      ssh_command(ssh, slug_install_command(slug_name_with_path, opts[:deploy_dir], {:owner => opts[:owner], :env => opts[:env], :force => opts[:force]}), logger)
      @slug_name = slug_name
      ActiveSupport::Notifications.publish('install.completed', {
        :host      => self,
        :ssh       => ssh,
        :slug_name => slug_name_with_path,
        :logger    => logger,
        :opts      => opts
      })
      record_event :installed
    end

    def file_count(ssh, path, file)
      ssh.exec!("find #{path} -maxdepth 1 -name '#{file}' -type f -size +0 | wc -l").to_i
    end

    def scp_upload(host, user, source, dest, logger, opts)
      logger.log "SCP: #{source} to #{host}:#{dest}"
      Net::SCP.upload!(host, user, source, dest, opts) do | ch, name, sent, total |
        logger.log "\r#{name}: #{(sent * 100.0 / total).to_i}% "
      end
      logger.log
    end

    def ssh_command(ssh, command, logger)
      output = ssh.exec!("#{command} ; echo \"SSH_COMMAND_EXIT_CODE=$?\"")
      exit_code_matches = /^SSH_COMMAND_EXIT_CODE=(\d+)$/.match(output)
      exit_code = exit_code_matches ? exit_code_matches[1].to_i : 0
      logger_opts = if exit_code == 0
                      {:color => :green, :log_level => :verbose}
                    else
                      {:color => :red}
                    end.merge({:status => :command})
      logger.log "#{command}", logger_opts
      logger.log "Output:\n#{output}", logger_opts
      @deploy_results << (result = {:exit_code => exit_code, :output => output, :command => command, :username => ssh.options[:user]})
      result
    end

    def slug_install_command(slug_name_with_path, deploy_dir, opts = {})
      [ opts[:prefix],
        "TERM=dumb sudo bash -l -c 'date >> /var/log/slug_deploy.log ; ",
        "chmod +x #{slug_name_with_path} ",
        "&& #{opts[:env]} #{slug_name_with_path} ",
        '-y ', #always clobber existing installs
        "-i #{deploy_dir} ",
        opts[:owner] ? "-o #{opts[:owner]} " : '',
        opts[:force] ? '-f ' : '',
        opts[:unpack] ? '-u ' : '',
        '-v ', #verbose
        "| tee -a /var/log/slug_deploy.log'"
      ].join('')
    end
  end
end
