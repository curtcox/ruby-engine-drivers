require 'uv-rays'

module Cisco; end
class Cisco::Cmx
    def initialize(host, user, pass)
        @host = UV::HttpEndpoint.new(host)
        @headers = {
            authorization: [user, pass]
        }
    end

    DECODE_OPTIONS = {
        symbolize_names: true
    }.freeze

    def locate(user: nil, ip: nil, mac: nil)
        query = { sortBy: 'lastLocatedTime:DESC' }
        query[:username] = user if user
        query[:ipAddress] = ip if ip
        query[:macAddress] = mac if mac

        resp = @host.get(path: '/api/location/v2/clients', headers: @headers, query: query).value

        return [] if resp.status == 204
        raise "request failed #{resp.status}\n#{resp.body}" if resp.status < 200 || resp.status > 200

        JSON.parse(resp.body, DECODE_OPTIONS)
    end
end
