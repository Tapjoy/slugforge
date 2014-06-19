require 'slugforge/models/host'

module Slugforge
  class IpAddressHost < Host
    def name
      "ip:#{@pattern}"
    end
  end
end
