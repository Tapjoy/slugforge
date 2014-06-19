require 'fog'

module Slugforge
  module Helper
    module Fog
      def compute
        @compute ||= ::Fog::Compute.new(aws_credentials.merge({
          :region   => config.ec2_region,
          :provider => 'AWS'
        }))
      end

      def autoscaling
        @autoscaling ||= ::Fog::AWS::AutoScaling.new(aws_credentials)
      end

      def s3
        @s3 ||= ::Fog::Storage.new(aws_credentials.merge({
          :provider => 'AWS'
        }))
      end

      def aws_credentials
        {
          :aws_access_key_id     => verify_aws_config(config.aws_access_key, 'access key'),
          :aws_secret_access_key => verify_aws_config(config.aws_secret_key, 'secret key'),
          :aws_session_token     => config.aws_session_token
        }.reject{ |_,v| v.nil? }
      end

      def aws_bucket
        config.slug_bucket || raise(error_class, "You must specify a slug bucket in your configuration")
      end

      def expiring_url(file, expiration=nil)
        expiration ||= Time.now + 60*60
        file.url(expiration)
      end

      # Create a temporary AWS session
      # @return [Hash] hash containing :access_key_id, :secret_access_key, :session_token
      def aws_session(duration = 30)
        @aws_session ||= begin
          sts = ::Fog::AWS::STS.new(aws_credentials)

          # Request a token for the user that has permissions masked to a single S3 bucket and only lasts a short time
          token = sts.get_federation_token( username, bucket_policy, duration * 60 ) # session duration in minutes

          {
            aws_access_key_id:     token.body['AccessKeyId'],
            aws_secret_access_key: token.body['SecretAccessKey'],
            aws_session_token:     token.body['SessionToken']
          }
        end
      end

      private
      def username
        `whoami`.chomp
      end

      def verify_aws_config(variable, message)
        raise error_class, "AWS #{message} is required to access AWS" unless variable
        variable
      end

      def bucket_policy(bucket = aws_bucket)
        {
          "Version"   => "2012-10-17",
          "Statement" => [
            {
              "Action"   => ["s3:*"],
              "Effect"   => "Allow",
              "Resource" => ["arn:aws:s3:::#{bucket}/*"]
            },
            {
              "Action"   => [
                 "s3:ListBucket"
              ],
              "Effect"   => "Allow",
              "Resource" => [ "arn:aws:s3:::#{bucket}" ]
            }
          ]
        }
      end
    end
  end
end

