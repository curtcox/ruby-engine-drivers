# frozen_string_literal: true

module Aca; end
module Aca::Tracking; end

# Manual desk tracking 
require 'aca/tracking/switch_port'
require 'set'

class Aca::Tracking::DeskManagement
    include ::Orchestrator::Constants



    descriptive_name 'ACA Desk Management'
    generic_name :DeskManagement
    implements :logic

    default_settings({
        mappings: {
            switch_ip: { 'port_id' => 'desk_id' }
        },
        checkin: {
            level_id: []
        },
        timezone: 'Singapore' # used for manual desk checkin
    })

    def on_load
        on_update

        # Load any manual check-in data
        @manual_checkin.each do |level|
            query = ::Aca::Tracking::SwitchPort.find_by_switch_ip(level)
            query.each do |detail|
                details = detail.details
                details[:level] = detail.level
                details[:manual_desk] = true
                details[:clash] = false

                username = details.username
                self[username] = details
                @manual_usage[desk_id] = username
                @manual_users << username
            end
        end

        # Should only call once
        get_usage
    end

    def on_update
        self[:hold_time]    = setting(:desk_hold_time) || 5.minutes.to_i
        self[:reserve_time] = @desk_reserve_time = setting(:desk_reserve_time) || 2.hours.to_i
        @user_identifier = setting(:user_identifier) || :login_name
        @timezone = setting(:timezone) || 'UTC'

        # { "switch_ip": { "port_id": "desk_id" } }
        @switch_mappings = setting(:mappings) || {}
        @desk_mappings = {}
        @switch_mappings.each do |switch_ip, ports|
            ports.each do |port, desk_id|
                @desk_mappings[desk_id] = [switch_ip, port]
            end
        end

        # { level_id: ["desk_id1", "desk_id2", ...] }
        @manual_checkin = setting(:checkin) || {}
        @manual_usage = {} # desk_id => username
        @manual_users = Set.new

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
        if switch_ip
            ::Aca::Tracking::SwitchPort.find_by_id("swport-#{switch_ip}-#{port}")&.details
        else # Check for manual checkin
            username = @manual_usage[desk_id]
            return nil unless username
            self[username]
        end
    end

    # Grabs the current user from the websocket connection
    # and if the user has a desk reserved, then they can reserve their desk
    def reserve_desk(time = @desk_reserve_time)
        user = current_user
        raise 'User not found' unless user

        username = user.__send__(@user_identifier)
        desk_details = self[username]
        return manual_checkout(desk_details) if desk_details[:manual_desk]

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

    def manual_checkin(level_id, desk_id)
        user = current_user
        raise 'User not found' unless user
        return false unless @manual_usage[desk_id].nil? && @manual_desks.include?(desk_id)

        cancel_reservation

        username = @manual_usage[desk_id] = user.__send__(@user_identifier)
        tracker = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{level_id}-#{desk_id}") || ::Aca::Tracking::SwitchPort.new
        tracker.reserved_by = tracker.username = username

        # Reserve for the remainder of the day
        Time.zone = @timezone
        now = tracker.unplug_time = Time.now.to_i
        tracker.reserve_time = Time.zone.now.tomorrow.midnight.to_i - now

        # To set the ID correctly
        tracker.level = tracker.switch_ip = level_id
        tracker.desk_id = tracker.interface = desk_id

        tracker.save!
        details = tracker.details
        details[:level] = level_id
        details[:manual_desk] = true
        details[:clash] = false

        @manual_usage[desk_id] = username
        @manual_users << username
        self[username] = details
    end

    protected

    def manual_checkout(details)
        level = details[:level]
        desk_id = details[:desk_id]
        username = details[:username]
        
        tracker = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{level}-#{desk_id}")
        tracker&.destroy

        @manual_usage.delete(desk_id)
        @manual_users.delete(username)
        self[username] = nil
    end

    def cleanup_manual_checkins
        remove = []

        @manual_usage.each do |desk_id, username|
            details = self[username]
            remove << details unless details.reserved?
        end

        remove.each do |details|
            manual_checkout(details)
        end
    end

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
            ids.concat(mappings.values)
            desk_ids[level] = ids
        end

        # Add any manual checkin desks to the data
        @manual_desks = Set.new
        @manual_checkin.each do |level, desks|
            self["#{level}:manual_checkin"] = desks
            ids = desk_ids[level] || []
            ids.concat(desks)
            desk_ids[level] = ids

            # List of all the manual check-in desks
            @manual_desks.merge(desks)
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
            manual_desk_ids = @manual_usage.keys

            # Apply the settings on thread for performance reasons
            levels.each do |level, desks|
                desks.users.each do |user|
                    username = user.username
                    manual_checkout(self[username]) if @manual_users.include?(username)
                    self[username] = user
                    self[user.reserved_by] = user if user.clash
                end

                desks.reserved_users.each do |user|
                    self[user.reserved_by] = user
                end

                # Map the used manually checked-in desks
                on_level = @manual_checkin[level] || []
                desks.manual = on_level & manual_desk_ids
            end

            # Apply the summaries now manual desk counts are accurate
            levels.each do |level, desks|
                self[level] = desks.inuse + desks.manual
                self["#{level}:clashes"] = desks.clash + desks.manual # manual checkin desks look like clashes on the map
                self["#{level}:reserved"] = desks.reserved
                o = self["#{level}:occupied_count"] = desks.inuse.length - desks.clash.length + desks.reserved.length + desks.manual.length
                self["#{level}:free_count"] = self["#{level}:desk_count"] - o
            end

            nil
        }.catch { |error|
            logger.print_error error, 'getting desk usage'
        }.finally {
            schedule.in('5s') { get_usage }
        }

        cleanup_manual_checkins
        schedule.every('10m') do
            cleanup_manual_checkins
        end
    end

    PortUsage = Struct.new(:inuse, :clash, :reserved, :users, :reserved_users, :manual)

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
                    details.desk_id = desk_id
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
