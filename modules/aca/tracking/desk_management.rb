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
        @desk_hold_time = setting(:desk_hold_time) || 5.minutes.to_i
        @desk_reserve_time = setting(:desk_reserve_time) || 2.hours.to_i
        @user_identifier = setting(:user_identifier) || :login_name

        # { "switch_ip": { "port_id": "desk_id" } }
        @switch_mappings = setting(:mappings) || {}
        @desk_mappings = {}
        @switch_mappings.each do |switch_ip, ports|
            ports.each do |port, desk_id|
                @desk_mappings[desk_id] = [switch_ip, port]
            end
        end
    end

    # these are helper functions for API usage
    def desk_usage(building, level)
        self["#{building}:#{level}"] || []
    end

    def desk_details(desk_id)
        switch_ip, port = @desk_mappings[desk_id]
        return nil unless switch_ip
        Aca::Tracking::SwitchPort.find_by_id("swport-#{switch_ip}-#{port}")
    end

    # Grabs the current user from the websocket connection
    # and if the user has a desk reserved, then they can reserve their desk
    def reserve_desk(time = @desk_reserve_time)
        user = current_user
        raise 'User not found' unless user

        username = user.__send__(@user_identifier)
        desk_details = self[username] || {}
        location = desk_details[:location]
        return 'Desk not found. Reservation time limit exceeded.' unless location

        switch_ip, port = @desk_mappings[location]
        reservation = Aca::Tracking::SwitchPort.find_by_id("swport-#{switch_ip}-#{port}")
        raise "Mapping error. Desk #{location} can't be found on the switch #{switch_ip}-#{port}" unless reservation
        return 'Desk not found. Reservation time limit exceeded.' unless reservation.reserved_by == username

        reservation.update_reservation(time)
    end

    def cancel_reservation
        reserve_desk(0)
    end

    #
    # TODO:: Callback for new user / callback 
    #

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
                    key = "#{building}:#{level}"
                    self[key] = desks[:inuse]
                    self["#{key}:#{clashes}"] = desks[:clash]
                    self["#{key}:#{reserved}"] = desks[:reserved]
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

        # Grab location information
        building = switch[:building]
        level = switch[:level]

        # Grab port information 
        interfaces = switch[:interfaces]
        reserved = switch[:reserved]

        # Build lookup structures
        b = buildings[building] ||= {}
        port_usage = b[level] ||= {
            inuse: [],
            clash: [],
            reserved: []
        }

        # Map the ports to desk IDs
        interfaces.each do |port|
            desk_id = map[port]
            if desk_id
                port_usage[:inuse] << desk_id
                port_usage[:clash] << desk_id if switch[port].clash
            else
                logger.debug { "Unknown port #{port} - no desk mapping found" }
            end
        end

        reserved.each do |port|
            desk_id = map[port]
            if desk_id
                port_usage[:reserved] << desk_id
            else
                logger.debug { "Unknown port #{port} - no desk mapping found" }
            end
        end

        nil
    end
end
