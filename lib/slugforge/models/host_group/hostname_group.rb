require 'slugforge/models/host/hostname_host'

module Slugforge
  class HostGroup ; end
  
  class HostnameGroup < HostGroup
    def self.matcher
      /^[^.]+\./
    end

    def initialize(pattern, compute)
      @hosts = [ HostnameHost.new(pattern) ]
      super
    end
  end
end
