require 'spec_helper'
require 'slugforge/models/host_group/ip_address_group'

describe Slugforge::IpAddressGroup do
  describe '.detect' do
    context 'valid address pattern' do
      let(:results) { described_class.detect(pattern, nil) }

      context 'short octets' do
        let(:pattern) { '1.2.3.4' }

        it 'returns an array with one element' do
          results.hosts.count.should == 1
        end

        it 'returns an array of IpAddressHosts' do
          results.hosts.select { |host| host.class == Slugforge::IpAddressHost }.count.should == results.hosts.count
        end
      end

      context 'long octets' do
        let(:pattern) { '123.234.111.222' }

        it 'returns an array with one element' do
          results.hosts.count.should == 1
        end

        it 'returns an array of IpAddressHosts' do
          results.hosts.select { |host| host.class == Slugforge::IpAddressHost }.count.should == results.hosts.count
        end
      end
    end

    context 'invalid address pattern' do
      let(:results) { described_class.detect(pattern, nil) }

      context 'the pattern contains letters' do
        let(:pattern) { '1.2.a.4' }
        it { results.should be_nil }
      end

      context 'the pattern contains less than 4 octets' do
        let(:pattern) { '1.2.3' }
        it { results.should be_nil }
      end

      context 'the pattern contains more than 4 octets' do
        let(:pattern) { '1.2.3.4.5' }
        it { results.should be_nil }
      end
    end
  end
end

