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
        mappings: {
            switch_ip: { 'port_id' => 'desk_id' }
        }
    })

    def on_load
        on_update

        # Should only call once
        get_usage
    end

    def on_update
        self[:hold_time]    = setting(:desk_hold_time) || 5.minutes.to_i
        self[:reserve_time] = @desk_reserve_time = setting(:desk_reserve_time) || 2.hours.to_i
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
        (self[level] || []) +
        (self["#{level}:reserved"] || [])
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
        hardware = switches

        # Build the list of desk ids for each level
        desk_ids = {}
        hardware.each do |switch|
            ip = switch[:ip_address]
            mappings = @switch_mappings[ip]
            next unless mappings

            level = switch[:level]
            ids = desk_ids[level] || []
            ids += mappings.values
            desk_ids[level] = ids
        end

        # Apply the level details
        desk_ids.each { |level, desks|
            self["#{level}:desk_ids"] = desks
            self["#{level}:desk_count"] = desks.length
        }

        # Watch for users unplugging laptops
        sys = system
        (1..hardware.length).each do |index|
            @subscriptions << sys.subscribe(:Snooping, index, :disconnected) do |notify|
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
            level_data = {}

            # Find the desks in use
            all_switches.each do |switch|
                apply_mappings(level_data, switch, mappings)
            end

            level_data
        }.then { |levels|
            # Apply the settings on thread for performance reasons
            levels.each do |level, desks|
                self[level] = desks.inuse
                self["#{level}:clashes"] = desks.clash
                self["#{level}:reserved"] = desks.reserved
                self["#{level}:occupied_count"] = desks.inuse.length - desks.clash.length + desks.reserved.length

                desks.users.each do |user|
                    self[user.username] = user
                    self[user.reserved_by] = user if user.clash
                end

                desks.reserved_users.each do |user|
                    self[user.reserved_by] = user
                end
            end
        }.finally {
            schedule.in('5s') { get_usage }
        }
    end

    PortUsage = Struct.new(:inuse, :clash, :reserved, :users, :reserved_users)

    def apply_mappings(level_data, switch, mappings)
        switch_ip = switch[:ip_address]
        map = mappings[switch_ip]
        if map.nil?
            logger.warn "no mappings for switch #{switch_ip}"
            return
        end

        # Grab port information 
        interfaces = switch[:interfaces]
        reservations = switch[:reserved]

        # Build lookup structures
        building = switch[:building]
        level = switch[:level]
        port_usage = level_data[level] ||= PortUsage.new([], [], [], [], [])

        # Prevent needless lookups
        inuse = port_usage.inuse
        clash = port_usage.clash
        reserved = port_usage.reserved
        users = port_usage.users
        reserved_users = port_usage.reserved_users

        # Map the ports to desk IDs
        interfaces.each do |port|
            desk_id = map[port]
            if desk_id
                details = switch[port]

                # Configure desk id if not known
                if details.desk_id != desk_id
                    details.level = level
                    details.desk_id = desk_id
                    details.building = building
                    ::User.bucket.subdoc("swport-#{switch_ip}-#{port}") do |doc|
                        doc.dict_upsert(:level, level)
                        doc.dict_upsert(:desk_id, desk_id)
                        doc.dict_upsert(:building, building)
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
