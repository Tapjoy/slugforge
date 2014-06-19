module Slugforge
  class Logger
    def initialize(thor_shell, log_level = :info)
      @thor_shell = thor_shell
      @log_level  = log_level
    end

    def log(message="", opts={})
      return if @log_level != :verbose && opts[:log_level] == :verbose
      if opts[:status]
        say_status opts[:status], message, opts[:color]
      else
        if opts[:force_new_line]
          say message, opts[:color], true
        else
          say message, opts[:color]
        end
      end
    end

    def say(message="", color=nil, force_new_line=(message.to_s !~ /( |\t)\z/))
      return if [:quiet, :json].include?(@log_level)
      @thor_shell.say message, color, force_new_line
    end

    def say_status(status, message, log_status=true)
      return if [:quiet, :json].include?(@log_level)
      @thor_shell.say_status status, message, log_status
    end

    def say_json(message)
      return unless @log_level == :json
      @thor_shell.say message.to_json
    end
  end
end
