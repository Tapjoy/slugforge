require 'slugforge/models/host/fog_host'

module Slugforge
  class HostGroup ; end
  
  class SecurityGroupGroup < HostGroup
    def self.matcher
      /\w+/
    end
    
    def initialize(pattern, compute)
      @hosts = compute.servers.select do |server|
        server.groups.include?(pattern) && !server.public_ip_address.nil?
      end.map do |server|
        FogHost.new(pattern, server)
      end
      super
    end
  end
end
