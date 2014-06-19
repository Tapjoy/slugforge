require 'slugforge/models/host/fog_host'

module Slugforge
  class HostGroup ; end
  
  class AwsTagGroup < HostGroup
    def self.matcher
      /^(\w+)=(\w+)$/
    end

    def initialize(pattern, compute)
      matches = self.class.matcher.match(pattern)
      return nil unless matches
      @hosts = compute.servers.select do |server|
        server.tags[matches[1]] == matches[2] && !server.public_ip_address.nil?
      end.map do |server|
        FogHost.new(pattern, server)
      end
      super
    end
  end
end
