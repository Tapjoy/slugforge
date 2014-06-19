require 'slugforge/models/host/fog_host'

module Slugforge
  class HostGroup ; end
  
  class Ec2InstanceGroup < HostGroup
    def self.matcher
      /^i-[0-9a-f]{8}$/i
    end

    def initialize(pattern, compute)
      server = compute.servers.get(pattern)
      @hosts = if server.nil? || server.public_ip_address.nil?
                 []
               else
                 [ FogHost.new(pattern, server) ]
               end
      super
    end
  end
end
