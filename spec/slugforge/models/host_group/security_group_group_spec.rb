require 'spec_helper'
require 'slugforge/models/host_group/security_group_group'

describe Slugforge::SecurityGroupGroup do
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
      let(:pattern) { 'group' }

      context 'one host is found' do
        before(:each) { server_objects.first.groups << pattern }

        it 'returns the array with one element' do
          results.hosts.count.should == 1
        end

        it 'returns an array of FogHosts' do
          results.hosts.select { |host| host.class == Slugforge::FogHost }.count.should == results.hosts.count
        end
      end

      context 'multiple hosts are found' do
        before(:each) { server_objects.each { |s| s.groups << pattern } }

        it 'returns the array with all hosts' do
          results.hosts.count.should == server_objects.count
        end

        it 'returns an array of FogHosts' do
          results.hosts.select { |host| host.class == Slugforge::FogHost }.count.should == results.hosts.count
        end
      end
    end

    context 'no hosts are found' do
      let(:results) { described_class.detect(pattern, compute) }
      let(:pattern) { 'name=value' }
      it { results.should be_nil }
    end
  end
end

