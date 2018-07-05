# frozen_string_literal: true
# encoding: ASCII-8BIT

module Cisco; end
module Cisco::Wireless; end

class Cisco::Wireless::CmxZones
    include ::Orchestrator::Constants

    descriptive_name 'Cisco CMX Zone Management'
    generic_name :FloorManagement
    implements :service

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
        @levels = settings(:levels) || {}

        config({
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
                    self[zone_id.to_s] = data['Count']
                rescue => e
                    :abort
                end
            else
                :abort
            end
        end
    end

    protected

    def build_zone_list
        @levels.each do |name, level|
            zone_id = level[:id]
            values = {}

            # Grab all the counts
            counts = level[:zones].collect do |zone|
                get_count(zone[:cmx_id]).then do |count|
                    values[zone[:map_id]] = {
                        capacity: zone[:capacity],
                        people_count: count
                    }
                end
            end

            # Wait for all the requests to complete
            thread.all(*counts).finally { self[zone_id] = values }
        end
    end
end
