require 'slugforge/models/host/ip_address_host'

module Slugforge
  class HostGroup ; end
  
  class IpAddressGroup < HostGroup
    def self.matcher
      /^(\d{1,3}\.){3}(\d{1,3})$/
    end
    
    def initialize(pattern, compute)
      @hosts = [ IpAddressHost.new(pattern) ]
      super
    end
  end
end
