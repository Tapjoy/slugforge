module Slugforge
  module Helper
    module Config
      def self.included(base)
        base.class_option :'aws-access-key-id', :type => :string, :aliases => '-I', :group => :config,
          :desc => 'The AWS Access ID to use for hosts and buckets, unless overridden'
        base.class_option :'aws-secret-key', :type => :string, :aliases => '-S', :group => :config,
          :desc => 'The AWS Secret Key to use for hosts and buckets, unless overridden'
        base.class_option :'aws-region', :type => :string, :group => :config,
          :desc => 'The AWS region to use for EC2 instances and buckets'
        base.class_option :'slug-bucket', :type => :string, :group => :config,
          :desc => 'The S3 bucket to store the slugs and tags in'
        base.class_option :'aws-session-token', :type => :string, :group => :config,
          :desc => 'The AWS Session Token to use for hosts and buckets'

        base.class_option :project, :type => :string, :aliases => '-P', :group => :config,
          :desc => 'The name of the project as it exists in Slugforge. See the Project Naming section in the main help.'

        base.class_option :'ssh-username', :type => :string, :aliases => '-u', :group => :config,
          :desc => 'The account used to log in to the host (requires sudo privileges)'

        base.class_option :'disable-slugins', :type => :boolean, :group => :config,
          :desc => 'Disable slugin loading'

        base.class_option :verbose, :type => :boolean, :aliases => '-V', :group => :runtime,
          :desc => 'Display verbose output'
        base.class_option :json, :type => :boolean, :aliases => '-j', :group => :runtime,
          :desc => 'Display JSON output'

        # Options intended for slugforge developers
        base.class_option :test, :type => :boolean, :group => :runtime, :hide => true,
          :desc => 'Test mode. Behaves like --pretend but triggers notifications and side effects as if a real action was taken.'
      end
    end
  end
end

