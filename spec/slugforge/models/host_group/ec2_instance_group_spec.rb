require 'spec_helper'
require 'slugforge/models/host_group/ec2_instance_group'

describe Slugforge::Ec2InstanceGroup do
  let(:compute) { ::Fog::Compute.new(:provider => 'AWS', :aws_access_key_id => '', :aws_secret_access_key => '') }
  
  let(:server_objects) do
    3.times.map { compute.servers.create }.each { |s| s.wait_for { ready? } }
  end

  after(:each) do
    server_objects.each { |server| server.destroy }
  end

  describe '.detect' do
    context 'valid instance' do
      let(:results) { described_class.detect(pattern, compute) }
      let(:pattern) { server_objects.first.id }

      it 'returns the array with one element' do
        results.hosts.count.should == 1
      end
      
      it 'returns an array of FogHosts' do
        results.hosts.select { |host| host.class == Slugforge::FogHost }.count.should == results.hosts.count
      end
    end

    context 'invalid instance' do
      context 'pattern is too short' do
        let(:results) { described_class.detect(pattern, compute) }
        let(:pattern) { 'i-1234567' }
        it { results.should be_nil }
      end

      context 'pattern is too long' do
        let(:results) { described_class.detect(pattern, compute) }
        let(:pattern) { 'i-123456789' }
        it { results.should be_nil }
      end

      context 'instance does not exist' do
        let(:results) { described_class.detect(pattern, compute) }
        # This host *could* exist, but it's a long shot
        let(:pattern) { 'i-00000000' }
        it { results.should be_nil }
      end
    end
  end
end

