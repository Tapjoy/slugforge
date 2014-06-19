require 'spec_helper'
require 'slugforge/models/host_group/hostname_group'

describe Slugforge::HostnameGroup do
  describe '.detect' do
    context 'the pattern matches' do
      let(:results) { described_class.detect(pattern, nil) }
      let(:pattern) { 'ec2-something.compute-1.amazon.aws.com' }
      
      it 'returns the array with one element' do
        results.hosts.count.should == 1
      end
      
      it 'returns an array of HostnameHosts' do
        results.hosts.select { |host| host.class == Slugforge::HostnameHost }.count.should == results.hosts.count
      end
    end
  end
end

