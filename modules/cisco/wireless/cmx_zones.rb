# frozen_string_literal: true
# encoding: ASCII-8BIT

module Cisco; end
module Cisco::Wireless; end

# This expects the debug flag turned on in the Zone Count Register API under configuration service /api/config/v1/zoneCountParams/1.
# Details here: https://communities.cisco.com/message/267538#267538

=begin

get_count example response:
{
   "MacAddress": [
        "00:00:2a:01:00:41",
        "00:00:2a:01:00:50",
        "00:00:2a:01:00:3f",
        "00:00:2a:01:00:46",
        "00:00:2a:01:00:48",
        "00:00:2a:01:00:49",
        "00:00:2a:01:00:4c",
        "00:00:2a:01:00:4a"
    ],
    "Duration ": {
        "start": "2017/08/30 10:12:08",
        "end": "2017/08/30 10:22:08"
    },
    "Count ": 8
}

get_zones example response:
{
  "ZoneCounts": {
    "zoneCountList": [
      {
        "zoneId": 645,
        "hierarchy": "System Campus/Level 1/West",
        "zoneName": "West",
        "zoneCount": 0
      },
      { ... }
    ],
    "totalZones": 14,
    "duration": {
      "start": "2018/07/24 17:37:53",
      "end": "2018/07/24 17:47:53"
    }
  }
}

=end

class Cisco::Wireless::CmxZones
    include ::Orchestrator::Constants

    descriptive_name 'Cisco CMX Zone Management'
    generic_name :FloorManagement
    implements :service
    keepalive false

    default_settings({
        levels: {
            'Level 1' => {
                id: 'zone-ZQylhnqq',
                zones: [
                    {
                        name: 'West',
                        cmx_id: 639,
                        map_id: 'zone-2.N',
                        capacity: 100
                    }
                ]
            }
        }
    })

    def on_load
        on_update
    end

    def on_update
        @api_version = setting(:api_version) || 3
        @levels = setting(:levels) || {}

        defaults({
            headers: {
                authorization: [setting(:username), setting(:password)]
            }
        })

        schedule.clear
        schedule.every('60s', true) do
            build_zone_list
        end
    end

    def get_count(zone_id)
        get("/api/location/v#{@api_version}/clients/count/byzone/detail?zoneId=#{zone_id}", name: "zone_#{zone_id}") do |response|
            if response.status == 200
                begin
                    data = JSON.parse(response.body)
                    # CMX bug on count key with the trailing space
                    self[zone_id.to_s] = data['Count '] || data['Count']
                rescue
                    :abort
                end
            elsif response.status == 401
                login.then { get_count(zone_id) }
            else
                :abort
            end
        end
    end

    def get_zones
        get("/api/location/v#{@api_version}/clients/count/byzone", name: :all_zones) do |response|
            if response.status == 200
                begin
                    data = JSON.parse(response.body)
                    zones = {}
                    data['ZoneCounts']['zoneCountList'].each do |zone|
                        hierarchy = zone['hierarchy'].split('/')
                        zone_name = hierarchy[-1]
                        level = hierarchy[-2]
                        zones[level] ||= {}
                        zones[level][zone_name] = zone
                    end
                    self[:zone_counts] = zones
                    zones
                rescue
                    :abort
                end
            elsif response.status == 401
                login.then { get_zones }
            else
                :abort
            end
        end
    end

    def build_zone_list
        get_zones.then do |zones|
            @levels.each do |level_name, level|
                values = {}

                level[:zones].each do |zone|
                    data = zones[level_name][zone[:name]]
                    values[zone[:map_id]] = {
                        capacity: zone[:capacity],
                        people_count: data['zoneCount']
                    } if data
                end

                self[level[:id]] = values
            end
        end
    end

    protected

    def login
        post("/api/common/v#{@api_version}/login", name: :login) do |response|
            if (200..299).cover? response.status
                :success
            else
                logger.error 'CMX login error. Please check username and password.'
                :abort
            end
        end
    end
end
