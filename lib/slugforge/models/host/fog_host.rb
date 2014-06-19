require 'slugforge/models/host'

module Slugforge
  class FogHost < Host
    def name
      "instance:#{@server.id}, private_name:#{@server.private_dns_name}, public_name:#{@server.dns_name}, ip:#{@server.public_ip_address}"
    end

    def ip
      @server.public_ip_address
    end

    def ssh_host
      @server.dns_name
    end

    def id
      @server.id
    end

    def is_autoscaled?
      !@server.tags["aws:autoscaling:groupName"].nil?
    end

    def to_status
      super.merge({
        :instance_id => @server.id,
        :private_name => @server.private_dns_name,
        :public_name => @server.dns_name,
      })
    end
  end
end
