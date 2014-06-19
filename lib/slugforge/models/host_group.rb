require 'slugforge/models/host_group/ip_address_group'
require 'slugforge/models/host_group/ec2_instance_group'
require 'slugforge/models/host_group/hostname_group'
require 'slugforge/models/host_group/aws_tag_group'
require 'slugforge/models/host_group/security_group_group'

module Slugforge
  class HostGroup
    attr_reader :name, :hosts

    def self.discover(patterns, compute)
      patterns.map do |pattern|
        IpAddressGroup.detect(pattern, compute) ||
        Ec2InstanceGroup.detect(pattern, compute) ||
        HostnameGroup.detect(pattern, compute) ||
        AwsTagGroup.detect(pattern, compute) ||
        SecurityGroupGroup.detect(pattern, compute) ||
        # If nothing detected, return a "null" group
        HostGroup.new(pattern, compute)
      end
    end

    def initialize(pattern, compute)
      @name = pattern
    end

    def install_all
      return if @hosts.nil?
      @hosts.each { |host| host.add_action(:install) }
    end

    def install_percent_of_hosts(value)
      return if @hosts.nil?
      count = (@hosts.count * value / 100.0).ceil
      sorted_hosts[0...count].each { |host| host.add_action(:install) }
    end

    def install_number_of_hosts(value)
      return if @hosts.nil?
      count = [@hosts.count, value].min
      sorted_hosts[0...count].each { |host| host.add_action(:install) }
    end

    def sorted_hosts
      # We sort the hosts by IP to make the order deterministic before we filter
      # by number or percent. That way when we move from 5% to 10% we end up at
      # 10% of the hosts, not some value between 10% and 15%.
      @hosts.sort_by { |host| host.ip }
    end

    def success?
      @hosts.all?(&:success?)
    end

    def hosts_for_action(action)
      @hosts.select { |host| host.has_action?(action) }
    end

    def self.detect(pattern, compute)
      return nil unless pattern =~ self.matcher
      group = self.new(pattern, compute)
      group.hosts.empty? ? nil : group
    end
  end
end
