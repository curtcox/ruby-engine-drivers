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

        # Bind to all the switches for disconnect notifications
        @subscriptions ||= []
        @subscriptions.each { |ref| unsubscribe(ref) }
        @subscriptions.clear
        subscribe_disconnect
    end

    # these are helper functions for API usage
    def desk_usage(building, level)
        (self["#{building}:#{level}"] || []) +
        (self["#{building}:#{level}:reserved"] || [])
    end

    def desk_details(desk_id)
        switch_ip, port = @desk_mappings[desk_id]
        return nil unless switch_ip
        ::Aca::Tracking::SwitchPort.find_by_id("swport-#{switch_ip}-#{port}")&.details
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
        reservation = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{switch_ip}-#{port}")
        raise "Mapping error. Desk #{location} can't be found on the switch #{switch_ip}-#{port}" unless reservation
        return 'Desk not found. Reservation time limit exceeded.' unless reservation.reserved_by == username

        reservation.update_reservation(time)
    end

    def cancel_reservation
        reserve_desk(0)
    end

    protected

    def switches
        system.all(:Snooping)
    end

    def subscribe_disconnect
        (1..switches.length).each do |index|
            @subscriptions << system.subscribe(:Snooping, index, :disconnected) do |notify|
                details = notify.value
                if details.reserved_by
                    self[details.reserved_by] = details
                end
            end
        end
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

            buildings
        }.then { |buildings|
            # Apply the settings on thread for performance reasons
            buildings.each do |building, levels|
                levels.each do |level, desks|
                    key = "#{building}:#{level}"
                    self[key] = desks[:inuse]
                    self["#{key}:clashes"] = desks[:clash]
                    self["#{key}:reserved"] = desks[:reserved]

                    desks[:users].each do |user|
                        self[user.username] = user
                        self[user.reserved_by] = user if user.clash
                    end

                    desks[:reserved_users].each do |user|
                        self[user.reserved_by] = user
                    end
                end
            end
        }.finally {
            schedule.in('5s') { desk_usage }
        }
    end

    def apply_mappings(buildings, switch, mappings)
        switch_ip = switch[:ip_address]
        map = mappings[switch_ip]
        if map.nil?
            logger.warn "no mappings for switch #{switch_ip}"
            return
        end

        # Grab location information
        building = switch[:building]
        level = switch[:level]

        # Grab port information 
        interfaces = switch[:interfaces]
        reservations = switch[:reserved]

        # Build lookup structures
        b = buildings[building] ||= {}
        port_usage = b[level] ||= {
            inuse: [],
            clash: [],
            reserved: [],
            users: [],
            reserved_users: []
        }

        # Prevent needless hash lookups
        inuse = port_usage[:inuse]
        clash = port_usage[:clash]
        reserved = port_usage[:reserved]
        users = port_usage[:users]
        reserved_users = port_usage[:reserved_users]

        # Map the ports to desk IDs
        interfaces.each do |port|
            desk_id = map[port]
            if desk_id
                details = switch[port]

                # Configure desk id if not known
                if details.desk_id != desk_id
                    details.desk_id = desk_id
                    ::User.bucket.subdoc("swport-#{switch_ip}-#{port}") do |doc|
                        doc.dict_upsert('desk_id', desk_id)
                    end
                end

                inuse << desk_id
                clash << desk_id if details.clash

                # set the user details
                users << details if details.username
            else
                logger.debug { "Unknown port #{port} - no desk mapping found" }
            end
        end

        reservations.each do |port|
            desk_id = map[port]
            if desk_id
                reserved << desk_id

                # set the user details (reserved_by must exist to be here)
                reserved_users << switch[port]
            else
                logger.debug { "Unknown port #{port} - no desk mapping found" }
            end
        end

        nil
    end
end
