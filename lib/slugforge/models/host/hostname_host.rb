require 'slugforge/models/host'

module Slugforge
  class HostnameHost < Host
    def name
      "hostname:#{@pattern}"
    end
  end
end
