# frozen_string_literal: true

module Aca; end
module Aca::Tracking; end

require 'aca/tracking/switch_port'

class Aca::Tracking::DeskManagement
    include ::Orchestrator::Constants

    descriptive_name 'ACA Desk Management'
    generic_name :DeskManagement
    implements :logic

    default_settings({
        'switch_ip' => { 'port_id' => 'desk_id' }
    })

    def on_load
        on_update

        # Should only call once
        get_usage
    end

    def on_update
        # { "switch_ip": { "port_id": "desk_id" } }
        @switch_mappings = setting(:mappings) || {}
        @desk_mappings = {}
        @switch_mappings.each do |switch_ip, ports|
            ports.each do |port, desk_id|
                @desk_mappings[desk_id] = [switch_ip, port]
            end
        end
    end

    def desk_usage(building, level)
        self["#{building}:#{level}"] || []
    end

    def desk_details(desk_id)
        switch_ip, port = @desk_mappings[desk_id]
        return nil unless switch_ip
        Aca::Tracking::SwitchPort.find_by_id("swport-#{switch_ip}-#{port}")
    end

    protected

    def switches
        system.all(:Snooping)
    end

    def get_usage
        # Get local vars in case they change while we are processing
        all_switches = switches.to_a
        mappings = @switch_mappings

        # Perform operations on the thread pool
        @caching = thread.work {
            buildings = {}

            # Find the desks in use
            all_switches.each do |switch|
                apply_mappings(buildings, switch, mappings)
            end

            # Cache the levels
            buildings.each do |building, levels|
                levels.each do |level, desks|
                    self["#{building}:#{level}"] = desks
                end
            end
        }.finally {
            schedule.in('5s') { desk_usage }
        }
    end

    def apply_mappings(buildings, switch, mappings)
        map = mappings[switch[:ip_address]]
        if map.nil?
            logger.warn "no mappings for switch #{switch[:ip_address]}"
            return
        end

        # Grab switch information
        interfaces = switch[:interfaces]
        building = switch[:building]
        level = switch[:level]

        # Build lookup structures
        b = buildings[building] ||= {}
        inuse = b[level] ||= []

        # Map the ports to desk IDs
        interfaces.each do |port|
            desk_id = map[port]
            inuse << desk_id if desk_id
        end
    end
end
