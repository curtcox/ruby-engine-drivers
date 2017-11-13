require 'uv-rays'

# Documentation:
# https://www.cisco.com/c/en/us/td/docs/wireless/mse/10-2/api/b_cmx_102_api_reference/b-cmx-102-api-reference-guide_chapter_011.html

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
        raise "request failed #{resp.status}\n#{resp.body}" unless (200...300).include?(resp.status)

        JSON.parse(resp.body, DECODE_OPTIONS)
    end
end
