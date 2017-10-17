# encoding: ASCII-8BIT


# For rounding up to the nearest 15min
# See: http://stackoverflow.com/questions/449271/how-to-round-a-time-down-to-the-nearest-15-minutes-in-ruby
class ActiveSupport::TimeWithZone
    def ceil(seconds = 60)
        return self if seconds.zero?
        Time.at(((self - self.utc_offset).to_f / seconds).ceil * seconds).in_time_zone + self.utc_offset
    end
end


module IBM; end
module IBM::Domino; end


class IBM::Domino::Bookings
    include ::Orchestrator::Constants

    descriptive_name 'IBM Domino Room Bookings'
    generic_name :Bookings
    implements :logic

    # The room we are interested in
    default_settings({
        update_every: '2m'
    })


    def on_load
        on_update
    end

    def on_update
        self[:hide_all] = setting(:hide_all) || false
        self[:touch_enabled] = setting(:touch_enabled) || false
        self[:name] = self[:room_name] = setting(:room_name) || system.name

        self[:control_url] = setting(:booking_control_url) || system.config.support_url
        self[:booking_controls] = setting(:booking_controls)
        self[:booking_catering] = setting(:booking_catering)
        self[:booking_hide_details] = setting(:booking_hide_details)
        self[:booking_hide_availability] = setting(:booking_hide_availability)
        self[:booking_hide_user] = setting(:booking_hide_user)
        self[:booking_hide_description] = setting(:booking_hide_description)
        self[:booking_hide_timeline] = setting(:booking_hide_timeline)

        # Is there catering available for this room?
        self[:catering] = setting(:catering_system_id)
        if self[:catering]
            self[:menu] = setting(:menu)
        end

        # Load the last known values (persisted to the DB)
        self[:waiter_status] = (setting(:waiter_status) || :idle).to_sym
        self[:waiter_call] = self[:waiter_status] != :idle

        self[:catering_status] = setting(:last_catering_status) || {}
        self[:order_status] = :idle

        self[:last_meeting_started] = setting(:last_meeting_started)
        self[:cancel_meeting_after] = setting(:cancel_meeting_after)

        fetch_bookings
        schedule.clear
        schedule.every(setting(:update_every) || '5m') { fetch_bookings }
    end


    def set_light_status(status)
        lightbar = system[:StatusLight]
        return if lightbar.nil?

        case status.to_sym
        when :unavailable
            lightbar.colour(:red)
        when :available
            lightbar.colour(:green)
        when :pending
            lightbar.colour(:orange)
        else
            lightbar.colour(:off)
        end
    end


    # ======================================
    # Waiter call information
    # ======================================
    def waiter_call(state)
        status = is_affirmative?(state)

        self[:waiter_call] = status

        # Used to highlight the service button
        if status
            self[:waiter_status] = :pending
        else
            self[:waiter_status] = :idle
        end

        define_setting(:waiter_status, self[:waiter_status])
    end

    def call_acknowledged
        self[:waiter_status] = :accepted
        define_setting(:waiter_status, self[:waiter_status])
    end


    # ======================================
    # Catering Management
    # ======================================
    def catering_status(details)
        self[:catering_status] = details

        # We'll turn off the green light on the waiter call button
        if self[:waiter_status] != :idle && details[:progress] == 'visited'
            self[:waiter_call] = false
            self[:waiter_status] = :idle
            define_setting(:waiter_status, self[:waiter_status])
        end

        define_setting(:last_catering_status, details)
    end

    def commit_order(order_details)
        self[:order_status] = :pending
        status = self[:catering_status]

        if status && status[:progress] == 'visited'
            status = status.dup
            status[:progress] = 'cleaned'
            self[:catering_status] = status
        end

        if self[:catering]
            sys = system
            @oid ||= 1
            systems(self[:catering])[:Orders].add_order({
                id: "#{sys.id}_#{@oid}",
                created_at: Time.now.to_i,
                room_id: sys.id,
                room_name: sys.name,
                order: order_details
            })
        end
    end

    def order_accepted
        self[:order_status] = :accepted
    end

    def order_complete
        self[:order_status] = :idle
    end



    # ======================================
    # ROOM BOOKINGS:
    # ======================================
    def fetch_bookings
        self[:today] = system[:Calendar].events.value.collect do |event|
            {
                :Start => event[:starting].utc.iso8601[0..18],
                :End => event[:ending].utc.iso8601[0..18],
                :Subject => event[:summary],
                :owner => event[:organizer] || ''
                # :setup => 0,
                # :breakdown => 0
            }
        end
    end


    # ======================================
    # Meeting Helper Functions
    # ======================================

    def start_meeting(meeting_ref)
        self[:last_meeting_started] = meeting_ref
        self[:meeting_pending] = meeting_ref
        self[:meeting_ending] = false
        self[:meeting_pending_notice] = false
        define_setting(:last_meeting_started, meeting_ref)
    end

    def cancel_meeting(start_time)
        calendar = system[:Calendar]
        events = calendar.events.value
        events.keep_if do |event|
            event[:start].to_i == start_time
        end
        events.each do |event|
            calendar.remove(event)
        end
    end

    # If last meeting started !== meeting pending then
    #  we'll show a warning on the in room touch panel
    def set_meeting_pending(meeting_ref)
        self[:meeting_ending] = false
        self[:meeting_pending] = meeting_ref
        self[:meeting_pending_notice] = true
    end

    # Meeting ending warning indicator
    # (When meeting_ending !== last_meeting_started then the warning hasn't been cleared)
    # The warning is only displayed when meeting_ending === true
    def set_end_meeting_warning(meeting_ref = nil, extendable = false)
        if self[:last_meeting_started].nil? || self[:meeting_ending] != (meeting_ref || self[:last_meeting_started])
            self[:meeting_ending] = true

            # Allows meeting ending warnings in all rooms
            self[:last_meeting_started] = meeting_ref if meeting_ref
            self[:meeting_canbe_extended] = extendable
        end
    end

    def clear_end_meeting_warning
        self[:meeting_ending] = self[:last_meeting_started]
    end
    # ---------

    def create_meeting(options)

    end
end
