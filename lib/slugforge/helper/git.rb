module Slugforge
  module Helper
    module Git

      SHA_MAX_LENGTH = 10

      def git_inside_work_tree?
        return @git_inside_work_tree unless @git_inside_work_tree.nil?
        @git_inside_work_tree = git_command('rev-parse --is-inside-work-tree') == 'true'
      end

      def git_user
        @git_user ||= git_command('config github.user')
      end

      def git_account
        return nil unless git_inside_work_tree? && !git_url.empty?
        @git_account ||= git_url.match(%r|[:/]([^/]+)/[^/]+(\.git)?$|)[1]
      end

      def git_repository
        return nil unless git_inside_work_tree? && !git_url.empty?
        @git_repository ||= git_url.match(%r|/([^/]+?)(\.git)?$|)[1]
      end

      def git_branch
        return nil unless git_inside_work_tree?
        @git_branch ||= begin
                          symbolic_ref = git_command('symbolic-ref HEAD')
                          symbolic_ref.sub(%r|^refs/heads/|, '')
                        end
      end

      def git_remote
        return nil unless git_inside_work_tree?
        @git_remote ||= git_command("config branch.#{git_branch}.remote")
        # If we are headless just assume origin so that we can still detect other values
        @git_remote.empty? ? 'origin' : @git_remote
      end

      def git_remote_sha(opts = {})
        return nil unless git_inside_work_tree?
        sha_length = opts[:sha_length] || SHA_MAX_LENGTH
        url        = opts[:url] || git_url
        branch     = opts[:branch] || git_branch

        @git_remote_sha = begin
                            if @git_remote_sha.nil? || opts[:memoize] == false
                              output = git_command("ls-remote #{url} #{branch}").split(" ").first
                              output =~ /^[0-9a-f]{40}$/i ? output : nil
                            else
                              @git_remote_sha
                            end
                          end

        return @git_remote_sha.slice(0...sha_length) unless @git_remote_sha.nil?
      end

      def git_sha(opts = {})
        raise error_class, "SHA can't be detected as this is not a git repository" unless git_inside_work_tree?
        sha_length = opts[:sha_length] || SHA_MAX_LENGTH
        @git_sha ||= git_command('rev-parse HEAD').chomp
        @git_sha.slice(0...sha_length)
      end

      def git_url
        return '' unless git_inside_work_tree?
        @git_url ||= git_command("config remote.#{git_remote}.url")
      end

      def build_git_url(account, repository)
        account    ||= git_account
        repository ||= git_repository
        "git@github.com:#{account}/#{repository}.git"
      end

      private
      def git_command(cmd)
        path = options[:path] ? "cd '#{options[:path]}' &&" : ""
        `#{path} git #{cmd} 2> /dev/null`.chomp
      end

      def git_info
        Hash[methods.select { |m| m.to_s =~/^git_/ }.map { |m| [ m.to_s, send(m) ] }]
      end
    end
  end
end

