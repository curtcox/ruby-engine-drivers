require 'uv-rays'

# Documentation:
# https://www.cisco.com/c/en/us/td/docs/wireless/mse/10-2/api/b_cmx_102_api_reference/b-cmx-102-api-reference-guide_chapter_011.html

module Cisco; end
class Cisco::Cmx
    def initialize(host, user, pass, use_ou = nil, floor_mappings: nil, ssid: nil, api_version: 2)
        @host = UV::HttpEndpoint.new(host)
        @ldap = Array(use_ou)
        @floor_mappings = floor_mappings
        @ssid = Array(ssid) if ssid
        @api_version = api_version
        @path = "/api/location/v#{api_version}/clients"
        @headers = {
            authorization: [user, pass]
        }
    end

    def locate(user: nil, ip: nil, mac: nil, sort: 'lastLocatedTime:DESC')
        query = {}
        query[:sortBy] = sort if sort
        query[:ipAddress] = ip if ip
        query[:macAddress] = mac if mac

        if user && !@ldap.empty?
            resp = nil
            @ldap.each do |ou|
                query[:username] = "CN=#{user}#{ou}"
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
        resp = @host.get(path: @path, headers: @headers, query: query).value

        return nil if resp.status == 204
        raise "request failed #{resp.status}\n#{resp.body}" unless (200...300).include?(resp.status)

        locations = JSON.parse(resp.body, symbolize_names: true)
        locations.select! { |loc| @ssid.include?(loc[:ssId]) } if @ssid
        return nil if locations.length == 0

        map = if @api_version == 3
            locations[0][:locationMapHierarchy].split('>')
        else
            locations[0][:mapInfo][:mapHierarchyString].split('>')
        end
        campus = @floor_mappings[map[0]]
        building = @floor_mappings[map[1]]
        x_max = nil
        y_max = nil

        if building.is_a?(Hash)
            level = building[map[2]]
            if level.is_a?(Hash)
                x_max = level[:x_max]
                y_max = level[:y_max]
                level = level[:id]
            else
                x_max = building[:x_max]
                y_max = building[:y_max]
                zone = building[map[3]]
                building = building[:id]
            end
        else
            level = @floor_mappings[map[2]]
            zone = @floor_mappings[map[3]]
        end

        location = locations[0]
        if @api_version == 3
            {
                x: location[:locationCoordinate][:x],
                y: location[:locationCoordinate][:y],
                x_max: x_max,
                y_max: y_max,
                confidence: (location[:confidenceFactor] / 2),
                last_seen: location[:timestamp] / 1000,
                user_active: location[:associated],
                campus: campus || map[0],
                building: building || map[1],
                level: level || map[2],
                zone: zone || map[3],
                map_id: location[:floorRefId]
            }
        else
            {
                x: location[:mapCoordinate][:x],
                y: location[:mapCoordinate][:y],
                x_max: location[:mapInfo][:floorDimension][:width],
                y_max: location[:mapInfo][:floorDimension][:length],
                confidence: (location[:confidenceFactor] / 2),
                last_seen: location[:changedOn] / 1000,
                user_active: location[:currentlyTracked],
                campus: campus || map[0],
                building: building || map[1],
                level: level || map[2],
                zone: zone || map[3],
                map_id: location[:mapInfo][:floorRefId]
            }
        end
    end
end
