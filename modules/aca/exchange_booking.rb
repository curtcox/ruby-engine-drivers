require 'microsoft/exchange'

module Aca; end
class Aca::ExchangeBooking
    include ::Orchestrator::Constants
    descriptive_name 'MS Exchange (EWS) Room Booking Panel Logic'
    generic_name :Bookings
    implements :logic

    CAN_EWS = begin
        require 'viewpoint2'
        true
    rescue LoadError
        begin
            require 'viewpoint'
            true
        rescue LoadError
            false
        end
        false
    end

    # The room we are interested in
    default_settings({
        update_every: '2m',
        ews_url: 'https://example.com/EWS/Exchange.asmx',
        ews_user: 'service_account',
        ews_password: 'service account password',
        booking_cancel_email_message: 'The Stop button was pressed on the room booking panel',
        booking_timeout_email_message: 'The Start button was not pressed on the room booking panel'
    })

    def on_load
        self[:today] = []
        on_update
    end

    def on_update
        @use_act_as = setting(:use_act_as)
        self[:room_name] = setting(:room_name) || system.name
        self[:hide_all] = setting(:hide_all) || false
        self[:touch_enabled] = setting(:touch_enabled) || false
        self[:arrow_direction] = setting(:arrow_direction)
        self[:hearing_assistance] = setting(:hearing_assistance)
        self[:timeline_start] = setting(:timeline_start)
        self[:timeline_end] = setting(:timeline_end)
        self[:description] = setting(:description)
        self[:icon] = setting(:icon)
        self[:control_url] = setting(:booking_control_url) || system.config.support_url

        self[:timeout] = setting(:timeout)
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
        self[:booking_default_title] = setting(:booking_default_title) || "On the spot booking"
        self[:booking_select_free] = setting(:booking_select_free)
        self[:booking_hide_all] = setting(:booking_hide_all) || false
        @hide_all_day_bookings = Boolean(setting(:hide_all_day_bookings))

        @check_meeting_ending = setting(:check_meeting_ending) # seconds before meeting ending
        @extend_meeting_by = setting(:extend_meeting_by) || 15.minutes.to_i

        # Do we want to look up the users email address?
        if CAN_LDAP
            @ldap_creds = setting(:ldap_creds)
            if @ldap_creds
                encrypt = @ldap_creds[:encryption]
                encrypt[:method] = encrypt[:method].to_sym if encrypt && encrypt[:method]
                @tree_base = setting(:tree_base)
                @ldap_user = @ldap_creds.delete :auth
            end
        else
            logger.warn "net/ldap gem not available" if setting(:ldap_creds)
        end

        # Do we want to use exchange web services to manage bookings
        if CAN_EWS

            office_client_id = setting(:office_client_id)
            office_secret = setting(:office_secret)
            office_token_url = setting(:office_token_url)
            @office_room = (setting(:office_room) || system.email)
            

            @ews_creds = setting(:ews_creds)
            @ews_room = (setting(:ews_room) || system.email) if @ews_creds
            # supports: SMTP, PSMTP, SID, UPN (user principle name)
            # NOTE:: Using UPN we might be able to remove the LDAP requirement
            @ews_connect_type = (setting(:ews_connect_type) || :SMTP).to_sym
            @timezone = setting(:room_timezone)
        else
            logger.warn "viewpoint gem not available" if setting(:ews_creds)
        end

        self[:last_meeting_started] = setting(:last_meeting_started)
        self[:cancel_meeting_after] = setting(:cancel_meeting_after)

        schedule.clear
        schedule.in(rand(10000)) {
            fetch_bookings(true)
        }
        schedule.every((setting(:update_every) || 120000).to_i + rand(10000)) {
            fetch_bookings
        }
    end



    # ======================================
    # ROOM BOOKINGS:
    # ======================================
    def fetch_bookings(first=false)
        logger.debug { "looking up todays emails for #{@ews_room}" }
        task {
            todays_bookings(first)
        }.then(proc { |bookings|
            self[:today] = bookings
            if @check_meeting_ending
                should_notify?
            end
        }, proc { |e| logger.print_error(e, 'error fetching bookings') })
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

    def cancel_meeting(start_time, reason = "timeout")
        task {
            if start_time.class == Integer
                start_time = (start_time / 1000).to_i
                delete_ews_booking start_time
            else
                # Converts to time object regardless of start_time being string or time object
                start_time = Time.parse(start_time.to_s).to_i
                delete_ews_booking start_time
            end
        }.then(proc { |count|
            logger.warn { "successfully removed #{count} bookings due to #{reason}" }

            start_meeting(start_time * 1000)

            fetch_bookings
            true
        }, proc { |error|
            logger.print_error error, 'removing ews booking'
        })
    end

    # If last meeting started !== meeting pending then
    #  we'll show a warning on the in room touch panel
    def set_meeting_pending(meeting_ref)
        return if self[:last_meeting_started] == meeting_ref
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
        # Check that the required params exist
        required_fields = [:start, :end]
        check = required_fields - options.keys.collect(&:to_sym)
        if check != []
            # There are missing required fields
            logger.info "Required fields missing: #{check}"
            raise "missing required fields: #{check}"
        end

        req_params = {}
        req_params[:room_email] = @ews_room
        req_params[:subject] = options[:title]
        req_params[:start_time] = Time.at(options[:start].to_i / 1000).utc.iso8601.chop
        req_params[:end_time] = Time.at(options[:end].to_i / 1000).utc.iso8601.chop

        make_ews_booking req_params
        fetch_bookings
        logger.debug { "successfully created booking: #{id}" }
        "Ok"
    end

    def should_notify?
        bookings = self[:today]
        return unless bookings.present?
        now = Time.now.to_i

        current = nil
        pending = nil
        found = false

        bookings.sort! { |a, b| a[:end_epoch] <=> b[:end_epoch] }
        bookings.each do |booking|
            starting = booking[:start_epoch]
            ending = booking[:end_epoch]

            if starting < now && ending > now
                found = true
                current = ending
                @current_meeting_title = booking[:Subject]
            elsif found
                pending = starting
                break
            end
        end

        if !current
            self[:meeting_canbe_extended] = false
            return
        end

        check_start = current - @check_meeting_ending
        check_extend = current + @extend_meeting_by

        if now >= check_start && (pending.nil? || pending >= check_extend)
            self[:meeting_canbe_extended] = current
        else
            self[:meeting_canbe_extended] = false
        end
    end

    def extend_meeting
        starting = self[:meeting_canbe_extended]
        return false unless starting

        ending = starting + @extend_meeting_by
        create_meeting(start: starting * 1000, end: ending * 1000, title: @current_meeting_title).then do
            start_meeting(starting * 1000)
        end
    end

    def send_email(title, body, to)
        task {
            cli = Viewpoint::EWSClient.new(*@ews_creds)
            opts = {}

            if @use_act_as
                opts[:act_as] = @ews_room if @ews_room
            else
                cli.set_impersonation(Viewpoint::EWS::ConnectingSID[@ews_connect_type], @ews_room) if @ews_room
            end

            cli.send_message subject: title, body: body, to_recipients: to
        }
    end


    protected


    # =======================================
    # EWS Requests to occur in a worker thread
    # =======================================
    def make_ews_booking(user_email: nil, subject: 'On the spot booking', room_email:, start_time:, end_time:)
        user_email ||= self[:email]  # if swipe card used

        booking = {
            subject: subject,
            start: start_time,
            end: end_time
        }

        if user_email
            booking[:required_attendees] = [{
                attendee: { mailbox: { email_address: user_email } }
            }]
        end

        cli = Viewpoint::EWSClient.new(*@ews_creds)
        opts = {}

        if @use_act_as
            opts[:act_as] = @ews_room if @ews_room
        else
            cli.set_impersonation(Viewpoint::EWS::ConnectingSID[@ews_connect_type], @ews_room) if @ews_room
        end

        folder = cli.get_folder(:calendar, opts)
        appointment = folder.create_item(booking)

        # Return the booking IDs
        appointment.item_id
    end

    def delete_ews_booking(delete_at)
        now = Time.now
        timeout = delete_at + (self[:booking_cancel_timeout] || self[:timeout]) + 120
        if now.to_i > timeout
          start_meeting(delete_at * 1000)
          return 0
        end

        if @timezone
            start  = now.in_time_zone(@timezone).midnight
            ending = now.in_time_zone(@timezone).tomorrow.midnight
        else
            start  = now.midnight
            ending = now.tomorrow.midnight
        end

        count = 0

        cli = Viewpoint::EWSClient.new(*@ews_creds)

        if @use_act_as
            # TODO:: think this line can be removed??
            # delete_at = Time.parse(delete_at.to_s).to_i

            opts = {}
            opts[:act_as] = @ews_room if @ews_room

            folder = cli.get_folder(:calendar, opts)
            items = folder.items({:calendar_view => {:start_date => start.utc.iso8601, :end_date => ending.utc.iso8601}})
        else
            cli.set_impersonation(Viewpoint::EWS::ConnectingSID[@ews_connect_type], @ews_room) if @ews_room
            items = cli.find_items({:folder_id => :calendar, :calendar_view => {:start_date => start.utc.iso8601, :end_date => ending.utc.iso8601}})
        end

        items.each do |meeting|
            meeting_time = Time.parse(meeting.ews_item[:start][:text])

            # Remove any meetings that match the start time provided
            if meeting_time.to_i == delete_at
                # new_booking = meeting.update_item!({ end: Time.now.utc.iso8601.chop })

                meeting.delete!(:recycle, send_meeting_cancellations: 'SendOnlyToAll')
                count += 1
            end
        end
        count
    end

    def todays_bookings(first=false)
        now = Time.now
        if @timezone
            start  = now.in_time_zone(@timezone).midnight
            ending = now.in_time_zone(@timezone).tomorrow.midnight
        else
            start  = now.midnight
            ending = now.tomorrow.midnight
        end

        cli = Viewpoint::EWSClient.new(*@ews_creds)


        if @use_act_as
            opts = {}
            opts[:act_as] = @ews_room if @ews_room

            folder = cli.get_folder(:calendar, opts)
            items = folder.items({:calendar_view => {:start_date => start.utc.iso8601, :end_date => ending.utc.iso8601}})
        else
            cli.set_impersonation(Viewpoint::EWS::ConnectingSID[@ews_connect_type], @ews_room) if @ews_room
            items = cli.find_items({:folder_id => :calendar, :calendar_view => {:start_date => start.utc.iso8601, :end_date => ending.utc.iso8601}})
        end

        now_int = now.to_i

        # items.select! { |booking| !booking.cancelled? }
        results = items.collect do |meeting|
            item = meeting.ews_item
            start = item[:start][:text]
            ending = item[:end][:text]

            real_start = Time.parse(start)
            real_end = Time.parse(ending)

            # Extract the skype meeting URL
            if @timezone
                start = Time.parse(start).in_time_zone(@timezone).iso8601[0..18]
                ending = Time.parse(ending).in_time_zone(@timezone).iso8601[0..18]
            end

            logger.debug { item.inspect }

            if @hide_all_day_bookings
                next if Time.parse(ending) - Time.parse(start) > 86399
            end

            if ["Private", "Confidential"].include?(meeting.sensitivity)
                subject = meeting.sensitivity
                booking_owner = "Private"
            else
                subject = item[:subject][:text]
                booking_owner = item[:organizer][:elems][0][:mailbox][:elems][0][:name][:text]
            end

            {
                :Start => start,
                :End => ending,
                :Subject => subject,
                :owner => booking_owner,
                :setup => 0,
                :breakdown => 0,
                :start_epoch => real_start.to_i,
                :end_epoch => real_end.to_i
            }
        end
        results.compact!
    end
end