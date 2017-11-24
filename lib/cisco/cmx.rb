require 'uv-rays'

# Documentation:
# https://www.cisco.com/c/en/us/td/docs/wireless/mse/10-2/api/b_cmx_102_api_reference/b-cmx-102-api-reference-guide_chapter_011.html

module Cisco; end
class Cisco::Cmx
    def initialize(host, user, pass, use_ou = nil)
        @host = UV::HttpEndpoint.new(host)
        @ldap = Array(use_ou)
        @headers = {
            authorization: [user, pass]
        }
    end

    DECODE_OPTIONS = {
        symbolize_names: true
    }.freeze

    def locate(user: nil, ip: nil, mac: nil)
        query = { sortBy: 'lastLocatedTime:DESC' }
        query[:ipAddress] = ip if ip
        query[:macAddress] = mac if mac

        if user && !@ldap.empty?
            resp = nil
            @ldap.each do |ou|
                query[:username] = "CN=#{user},#{ou}"
                resp = perform(query)
                break if resp
            end
            resp
        else
            query[:username] = user if user
            perform(query)
        end
    end

    protected

    def perform(query)
        resp = @host.get(path: '/api/location/v2/clients', headers: @headers, query: query).value

        return nil if resp.status == 204
        raise "request failed #{resp.status}\n#{resp.body}" unless (200...300).include?(resp.status)

        locations = JSON.parse(resp.body, DECODE_OPTIONS)
        return nil if locations.length == 0

        location = {
            x: locations[0][:mapCoordinate][:x],
            y: locations[0][:mapCoordinate][:y],
            x_max: locations[0][:floorDimension][:width],
            y_max: locations[0][:floorDimension][:length],
            confidence: (locations[0][:confidenceFactor] / 2),
            last_seen: locations[0][:changedOn] / 1000
        }
    end
end
