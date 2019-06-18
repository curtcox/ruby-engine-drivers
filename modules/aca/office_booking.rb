# encoding: ASCII-8BIT
require 'faraday'
require 'uv-rays'
require 'microsoft/office'
Faraday.default_adapter = :libuv

module Aca; end
class Aca::OfficeBooking
    include ::Orchestrator::Constants
    descriptive_name 'Office365 Room Booking Panel Logic'
    generic_name :Bookings
    implements :logic

    # Constants that the Room Booking Panel UI (ngx-bookings) will use
    RBP_AUTOCANCEL_TRIGGERED  = 'pending timeout'
    RBP_STOP_PRESSED        = 'user cancelled'

    # The room we are interested in
    default_settings({
        update_every: '2m',
        booking_cancel_email_message: 'The Stop button was presseed on the room booking panel',
        booking_timeout_email_message: 'The Start button was not pressed on the room booking panel'
    })

    def on_load
        on_update
    end

    def on_update
        self[:swiped] ||= 0
        @last_swipe_at = 0
        @use_act_as = setting(:use_act_as)

        self[:hide_all] = setting(:hide_all) || false
        self[:touch_enabled] = setting(:touch_enabled) || false
        self[:arrow_direction] = setting(:arrow_direction)
        self[:hearing_assistance] = setting(:hearing_assistance)
        self[:timeline_start] = setting(:timeline_start)
        self[:timeline_end] = setting(:timeline_end)
        self[:title] = setting(:title)
        self[:description] = setting(:description)
        self[:icon] = setting(:icon)
        self[:control_url] = setting(:booking_control_url) || system.config.support_url

        self[:booking_cancel_timeout] = UV::Scheduler.parse_duration(setting(:booking_cancel_timeout)) / 1000 if setting(:booking_cancel_timeout)   # convert '1m2s' to '62'
        self[:booking_cancel_email_message] = setting(:booking_cancel_email_message)
        self[:booking_timeout_email_message] = setting(:booking_timeout_email_message)
        self[:booking_controls] = setting(:booking_controls)
        self[:booking_catering] = setting(:booking_catering)
        self[:booking_hide_details] = setting(:booking_hide_details)
        self[:booking_hide_availability] = setting(:booking_hide_availability)
        self[:booking_hide_user] = setting(:booking_hide_user)
        self[:booking_hide_modal] = setting(:booking_hide_modal)
        self[:booking_hide_title] = setting(:booking_hide_title)
        self[:booking_hide_description] = setting(:booking_hide_description)
        self[:booking_hide_timeline] = setting(:booking_hide_timeline)
        self[:booking_set_host] = setting(:booking_set_host)
        self[:booking_set_title] = setting(:booking_set_title)
        self[:booking_set_ext] = setting(:booking_set_ext)
        self[:booking_search_user] = setting(:booking_search_user)
        self[:booking_disable_future] = setting(:booking_disable_future)
        self[:booking_min_duration] = setting(:booking_min_duration)
        self[:booking_max_duration] = setting(:booking_max_duration)
        self[:booking_duration_step] = setting(:booking_duration_step)
        self[:booking_endable] = setting(:booking_endable)
        self[:booking_ask_cancel] = setting(:booking_ask_cancel)
        self[:booking_ask_end] = setting(:booking_ask_end)
        self[:booking_default_title] = setting(:booking_default_title)
        self[:booking_select_free] = setting(:booking_select_free)
        self[:booking_hide_all] = setting(:booking_hide_all) || false

        logger.debug "Setting OFFICE"
        @office_client_id = setting(:office_client_id)
        @office_secret = setting(:office_secret)
        @office_scope = setting(:office_scope)
        @office_site = setting(:office_site)
        @office_token_url = setting(:office_token_url)
        @office_user_email = setting(:office_user_email)
        @office_user_password = setting(:office_user_password)
        @office_room = (setting(:office_room) || system.email)

        @client = ::Microsoft::Office.new({
            client_id:                  @office_client_id       || ENV['OFFICE_CLIENT_ID'],
            client_secret:              @office_secret          || ENV["OFFICE_CLIENT_SECRET"],
            app_site:                   @office_site            || ENV["OFFICE_SITE"]           || "https://login.microsoftonline.com",
            app_token_url:              @office_token_url       || ENV["OFFICE_TOKEN_URL"],
            app_scope:                  @office_scope           || ENV['OFFICE_SCOPE']          || "https://graph.microsoft.com/.default",
            graph_domain:               ENV['GRAPH_DOMAIN']     || "https://graph.microsoft.com",
            service_account_email:      @office_user_password   || ENV['OFFICE_ACCOUNT_EMAIL'],
            service_account_password:   @office_user_password   || ENV['OFFICE_ACCOUNT_PASSWORD'],
            internet_proxy:             @internet_proxy         || ENV['INTERNET_PROXY']
        })

        self[:last_meeting_started] = setting(:last_meeting_started)
        self[:cancel_meeting_after] = setting(:cancel_meeting_after)

        fetch_bookings
        schedule.clear
        schedule.every(setting(:update_every) || '5m') { fetch_bookings }
    end

    def fetch_bookings(*args)
        response = @client.get_bookings_by_user(user_id: @office_room, start_param: Time.now.midnight, end_param: Time.now.tomorrow.midnight)[:bookings]
        self[:today] = expose_bookings(response)
    end

    def create_meeting(options)
        # Check that the required params exist
        required_fields = ["start", "end"]
        check = required_fields - options.keys
        if check != []
            # There are missing required fields
            logger.info "Required fields missing: #{check}"
            raise "missing required fields: #{check}"
        end

        logger.debug "RBP>#{@office_room}>CREATE>INPUT:\n #{options}"
        req_params = {}
        req_params[:room_email] = @office_room
        req_params[:organizer] = options.dig(:host, :email) || @office_room
        req_params[:subject] = options[:title]
        req_params[:start_time] = Time.at(options[:start].to_i / 1000).utc.to_i
        req_params[:end_time] = Time.at(options[:end].to_i / 1000).utc.to_i

        # TODO:: Catch error for booking failure
        begin
            id = create_o365_booking req_params
        rescue Exception => e
            logger.debug e.message
            logger.debug e.backtrace.inspect
            raise e
        end
        logger.debug { "successfully created booking: #{id}" }
        schedule.in('2s') do
            fetch_bookings
        end
        "Ok"
    end

    def start_meeting(meeting_ref)
        self[:last_meeting_started] = meeting_ref
        self[:meeting_pending] = meeting_ref
        self[:meeting_ending] = false
        self[:meeting_pending_notice] = false
        define_setting(:last_meeting_started, meeting_ref)
    end

    def cancel_meeting(start_time, reason = "unknown reason")
        now = Time.now.to_i
        start_epoch = Time.parse(start_time).to_i
        ms_epoch = start_epoch * 1000
        too_early_to_cancel = now < start_epoch
        too_late_to_cancel = now > start_epoch + (self[:booking_cancel_timeout] || self[:timeout]) + 180 # allow up to 3mins of slippage, in case endpoint is not NTP synced
        bookings_to_cancel = bookings_with_start_time(start_epoch)

        if bookings_to_cancel == 1
            if reason == RBP_STOP_PRESSED
                delete_o365_booking(start_epoch, reason)
            elsif reason == RBP_AUTOCANCEL_TRIGGERED
                if !too_early_to_cancel && !too_late_to_cancel
                    delete_o365_booking(start_epoch, reason)
                else
                    logger.warn { "RBP>#{@office_room}>CANCEL>TOO_EARLY: Booking not cancelled with start time #{start_time}" } if too_early_to_cancel
                    logger.warn { "RBP>#{@office_room}>CANCEL>TOO_LATE: Booking not cancelled with start time #{start_time}" } if too_late_to_cancel
                end
            else  # an unsupported reason, just cancel the booking and add support to this driver.
                logger.error { "RBP>#{@office_room}>CANCEL>UNKNOWN_REASON: Cancelled booking with unknown reason, with start time #{start_time}" }
                delete_o365_booking(start_epoch, reason)
            end
        else
            logger.warn { "RBP>#{@office_room}>CANCEL>CLASH: No bookings cancelled as Multiple bookings (#{bookings_to_cancel}) were found with same start time #{start_time}" } if bookings_to_cancel > 1
            logger.warn { "RBP>#{@office_room}>CANCEL>NOT_FOUND: Could not find booking to cancel with start time #{start_time}" } if bookings_to_cancel == 0
        end
    
        self[:last_meeting_started] = ms_epoch
        self[:meeting_pending]      = ms_epoch
        self[:meeting_ending]       = false
        self[:meeting_pending_notice] = false
        true
    end

    def bookings_with_start_time(start_epoch)
        return 0 unless self[:today]
        booking_start_times = self[:today]&.map { |b| Time.parse(b[:Start]).to_i }
        return booking_start_times.count(start_epoch)
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

    protected

    def create_o365_booking(user_email: nil, subject: 'On the spot booking', room_email:, start_time:, end_time:, organizer:)
        new_booking = {
            subject:    subject,
            start:      { dateTime: start_time, timeZone: "UTC" },
            end:        { dateTime: end_time, timeZone: "UTC" },
            location:   { displayName: @office_room, locationEmailAddress: @office_room },
            attendees:  organizer ? [ emailAddress: { address: organizer, name: "User"}] : []
        }

        booking_json = new_booking.to_json
        logger.debug "RBP>#{@office_room}>CREATE:\n #{booking_json}"
        begin
            result = @client.create_booking(room_id: system.id, start_param: start_time, end_param: end_time, subject: subject, current_user:  {email: organizer, name: organizer})
        rescue => e
            logger.error "RBP>#{@office_room}>CREATE>ERROR: #{e}\nResponse:\n#{result}"
        else
            logger.debug "RBP>#{@office_room}>CREATE>SUCCESS:\n #{result}"
        end
        result['id']
    end

    def delete_o365_booking(delete_start_epoch, reason)
        bookings_deleted = 0
        return bookings_deleted unless self[:today]     # Exist if no bookings
        delete_start_time = Time.at(delete_start_epoch)

        self[:today].each_with_index do |booking, i|
            booking_start_epoch = Time.parse(booking[:Start]).to_i
            if booking[:isAllDay]
                logger.warn { "RBP>#{@office_room}>CANCEL>ALL_DAY: An All Day booking was NOT deleted, with start time #{delete_start_epoch}" }
            elsif booking[:email] == @office_room  # Bookings owned by the room need to be deleted, not declined
                response = @client.delete_booking(booking_id: booking[:id], mailbox: system.email)
                logger.warn { "RBP>#{@office_room}>CANCEL>ROOM_OWNED: A booking owned by the room was deleted, with start time #{delete_start_epoch}" }
            elsif booking_start_epoch == delete_start_epoch
                # Decline the meeting, with the appropriate message to the booker
                case reason
                when RBP_AUTOCANCEL_TRIGGERED
                    response = @client.decline_meeting(booking_id: booking[:id], mailbox: system.email, comment: self[:booking_timeout_email_message])
                when RBP_STOP_PRESSED
                    response = @client.decline_meeting(booking_id: booking[:id], mailbox: system.email, comment: self[:booking_cancel_email_message])
                else
                    response = @client.decline_meeting(booking_id: booking[:id], mailbox: system.email, comment: "The booking was cancelled due to \"#{reason}\" ")
                end
                logger.warn { "RBP>#{@office_room}>CANCEL>SUCCESS: Declined booking due to \"#{reason}\", with start time #{delete_start_epoch}" }
                if response == 200
                    bookings_deleted += 1
                    # self[:today].delete_at(i) This does not seem to notify the websocket, so call fetch_bookings instead
                    fetch_bookings
                end
            end
        end
        # Return the number of meetings removed
        bookings_deleted
    end

    def expose_bookings(bookings)
        results = []
        bookings.each{ |booking|
            tz = ActiveSupport::TimeZone.new(booking['start']['timeZone'])      # in tz database format: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
            start_utc   = tz.parse(booking['start']['dateTime']).utc            # output looks like: "2019-05-21 15:50:00 UTC"
            end_utc     = tz.parse(booking['end']['dateTime']).utc                  
            start_time  = start_utc.iso8601                                     # output looks like: "2019-05-21T15:50:00Z+08:00"
            end_time    = end_utc.iso8601

            name =  booking.dig('organizer','name')  || booking.dig('attendees',0,'name')
            email = booking.dig('organizer','email') || booking.dig('attendees',0,'email')

            subject = booking['subject']
            if ['private','confidential'].include?(booking['sensitivity'])
                name = "Private"
                subject = "Private"
            end

            results.push({
                :Start => start_time,
                :End => end_time,
                :Subject => subject,
                :id => booking['id'],
                :icaluid => booking['icaluid'],
                :owner => name,
                :email => email,
                :organizer => {:name => name, :email => email},
                :isAllDay => booking['isAllDay']
            })
        }
        results
    end
end