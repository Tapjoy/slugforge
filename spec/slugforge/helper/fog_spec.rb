require 'spec_helper'

describe Slugforge::Helper::Fog, :config => false do
  let(:command_class) do
    Class.new(Slugforge::Command) do
      include Slugforge::Helper::Config
      include Slugforge::Helper::Fog

      desc 'test', 'An example command'
      def test; end
    end
  end

  let(:options) {{ 'aws-access-key-id' => 'abc', 'aws-region' => 'north-pole-9', 'aws-secret-key' => '123', 'slug-bucket' => 'bucket' }}

  let(:command) { command_class.new [], options }

  context "#aws_credentials" do
    subject(:aws_credentials) { command.aws_credentials }

    it "should error without access key" do
      options.delete('aws-access-key-id')
      expect { aws_credentials }.to raise_error(/access key/)
    end

    it "should error without secret key" do
      options.delete('aws-secret-key')
      expect { aws_credentials }.to raise_error(/secret key/)
    end

    it "should not error without session token" do
      expect { aws_credentials }.to_not raise_error
    end

    context "response hash" do
      it "should include key and secret" do
        expect(aws_credentials).to eq({:aws_access_key_id => 'abc', :aws_secret_access_key => '123'})
      end

      context "when session token is set" do
        let(:options) {{ 'aws-access-key-id' => 'abc', 'aws-secret-key' => '123', 'aws-session-token' => 'xyz' }}

        it "should include session token" do
          expect(aws_credentials).to eq({
            :aws_session_token     => 'xyz',
            :aws_access_key_id     => 'abc',
            :aws_secret_access_key => '123'})
        end
      end
    end
  end

  context "#aws_session" do
    # Fog doesn't have an STS mock yet
    let(:response)    { build_sts_response }
    let(:session)     { response.body }
    let(:username)    { 'user name' }
    let(:sts)         { double(::Fog::AWS::STS, :get_federation_token => response) }

    before(:each) do
      ::Fog::AWS::STS.stub(:new) { sts }
    end

    it "should exchange aws credentials for a federation session token" do
      command.stub(:username).and_return(username)
      ::Fog::AWS::STS.should_receive(:new).with(command.aws_credentials) { sts }
      sts.should_receive(:get_federation_token).with(username, instance_of(Hash), instance_of(Fixnum))

      command.aws_session
    end

    it "should return a session hash matching what fog expects for credentials" do
      expect(command.aws_session).to eq({
        :aws_access_key_id     => session['AccessKeyId'],
        :aws_region            => options['aws-region'],
        :aws_secret_access_key => session['SecretAccessKey'],
        :aws_session_token     => session['SessionToken']
      })
    end
  end
end
