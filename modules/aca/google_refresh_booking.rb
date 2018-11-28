# encoding: ASCII-8BIT

require 'uv-rays'

# For rounding up to the nearest 15min
# See: http://stackoverflow.com/questions/449271/how-to-round-a-time-down-to-the-nearest-15-minutes-in-ruby
class ActiveSupport::TimeWithZone
    def ceil(seconds = 60)
        return self if seconds.zero?
        Time.at(((self - self.utc_offset).to_f / seconds).ceil * seconds).in_time_zone + self.utc_offset
    end
end


module Aca; end

# NOTE:: Requires Settings:
# ========================
# room_alias: 'rs.au.syd.L16Aitken',
# building: 'DP3',
# level: '16'

class Aca::GoogleRefreshBooking
    include ::Orchestrator::Constants
    EMAIL_CACHE = ::Concurrent::Map.new
    CAN_LDAP = begin
        require 'net/ldap'
        true
    rescue LoadError
        false
    end
    CAN_GOOGLE = begin
        require 'googleauth'
        require 'google/apis/admin_directory_v1'
        require 'google/apis/calendar_v3'
        true
    rescue LoadError
        false
    end


    descriptive_name 'Google Room Bookings using Refresh'
    generic_name :Bookings
    implements :logic


    # The room we are interested in
    default_settings({
        update_every: '2m',

        # Moved to System or Zone Setting
        # cancel_meeting_after: 900

        # Card reader IDs if we want to listen for swipe events
        card_readers: ['reader_id_1', 'reader_id_2'],

        # Optional LDAP creds for looking up emails
        ldap_creds: {
            host: 'ldap.org.com',
            port: 636,
            encryption: {
                method: :simple_tls,
                tls_options: {
                    verify_mode: 0
                }
            },
            auth: {
                  method: :simple,
                  username: 'service account',
                  password: 'password'
            }
        },
        tree_base: "ou=User,ou=Accounts,dc=org,dc=com",

        # Optional EWS for creating and removing bookings
        ews_creds: [
            'https://company.com/EWS/Exchange.asmx',
            'service account',
            'password',
            { http_opts: { ssl_verify_mode: 0 } }
        ],
        ews_room: 'room@email.address',

        # Optional EWS for creating and removing bookings
        google_organiser_location: 'attendees',
        google_client_id: '',
        google_secret: '',
        google_redirect_uri: '',
        google_scope: 'https://www.googleapis.com/auth/calendar',
        # google_scope: ENV['GOOGLE_APP_SCOPE'],
        # google_site: ENV["GOOGLE_APP_SITE"],
        # google_token_url: ENV["GOOGLE_APP_TOKEN_URL"],
        # google_options: {
        #     site: ENV["GOOGLE_APP_SITE"],
        #     token_url: ENV["GOOGLE_APP_TOKEN_URL"]
        # },
        # google_room: 'room@email.address'
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
        self[:name] = self[:room_name] = setting(:room_name) || system.name

        self[:control_url] = setting(:booking_control_url) || system.config.support_url
        self[:booking_controls] = setting(:booking_controls)
        self[:booking_catering] = setting(:booking_catering)
        self[:booking_hide_details] = setting(:booking_hide_details)
        self[:booking_hide_availability] = setting(:booking_hide_availability)
        self[:booking_hide_user] = setting(:booking_hide_user)
        self[:booking_hide_description] = setting(:booking_hide_description)
        self[:booking_hide_timeline] = setting(:booking_hide_timeline)

        # Skype join button available 2min before the start of a meeting
        @skype_start_offset = setting(:skype_start_offset) || 120

        # Skype join button not available in the last 8min of a meeting
        @skype_end_offset = setting(:skype_end_offset) || 480

        # Because restarting the modules results in a 'swipe' of the last read card
        ignore_first_swipe = true

        # Is there catering available for this room?
        self[:catering] = setting(:catering_system_id)
        if self[:catering]
            self[:menu] = setting(:menu)
        end

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
        if CAN_GOOGLE
            logger.debug "Setting GOOGLE"
            # :client_id     => "237647939013-k5c6ubsa1ddt9o861pinpm2d0hom644j.apps.googleusercontent.com",
            # :client_secret => "h0vEuCHMLNH5fTwXj3S8PvkE",
            # :calendar      => "aca@googexcite.cloud",
            # :redirect_url  => "http://google.aca.im" 
           
            @google_organiser_location = setting(:google_organiser_location)
            @google_client_id = setting(:google_client_id)
            @google_secret = setting(:google_client_secret)
            @google_redirect_uri = setting(:google_redirect_uri)
            @google_refresh_token = setting(:google_refresh_token)
            @google_admin_email = setting(:google_admin_email)
            @google_scope = setting(:google_scope)
            @google_room = (setting(:google_room) || system.email)
            @google_timezone = setting(:timezone) || "Sydney"
            # supports: SMTP, PSMTP, SID, UPN (user principle name)
            # NOTE:: Using UPN we might be able to remove the LDAP requirement
            @google_connect_type = (setting(:google_connect_type) || :SMTP).to_sym
            @timezone = setting(:room_timezone)
        else
            logger.warn "oauth2 gem not available"
        end

        # Load the last known values (persisted to the DB)
        self[:waiter_status] = (setting(:waiter_status) || :idle).to_sym
        self[:waiter_call] = self[:waiter_status] != :idle

        self[:catering_status] = setting(:last_catering_status) || {}
        self[:order_status] = :idle

        self[:last_meeting_started] = setting(:last_meeting_started)
        self[:cancel_meeting_after] = setting(:cancel_meeting_after)


        # unsubscribe to all swipe IDs if any are subscribed
        if @subs.present?
            @subs.each do |sub|
                unsubscribe(sub)
            end

            @subs = nil
        end

        # Are there any swipe card integrations
        if system.exists? :Security
            readers = setting(:card_readers)
            if readers.present?
                security = system[:Security]

                readers = readers.is_a?(Array) ? readers : [readers]
                sys = system
                @subs = []
                readers.each do |id|
                    @subs << sys.subscribe(:Security, 1, id.to_s) do |notice|
                        if ignore_first_swipe
                            ignore_first_swipe = false
                        else
                            swipe_occured(notice.value)
                        end
                    end
                end
            end
        end

        @google  = ::Google::Admin.new({
            admin_email: nil,
            domain: ENV['GOOGLE_DOMAIN']
        })

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


    def fetch_bookings(*args)    
        events = @google.get_bookings(email: system.email, start_param: DateTime.now - 1.day, end_param: DateTime.now + 1.day ) 
        
        task {
            todays_bookings(events)
        }.then(proc { |bookings|
            self[:today] = bookings
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
        # Check that the required params exist
        required_fields = ["start", "end"]
        check = required_fields - options.keys
        if check != []
            # There are missing required fields
            logger.info "Required fields missing: #{check}"
            raise "missing required fields: #{check}"
        end

        logger.debug "Passed Room options: --------------------"
        logger.debug options
        logger.debug options.to_json

        req_params = {}
        req_params[:room_email] = @ews_room
        req_params[:organizer] = options[:user_email]
        req_params[:subject] = options[:title]
        req_params[:start_time] = Time.at(options[:start].to_i / 1000).utc.iso8601.chop
        req_params[:end_time] = Time.at(options[:end].to_i / 1000).utc.iso8601.chop

       
        # TODO:: Catch error for booking failure
        begin
            id = make_google_booking req_params
        rescue Exception => e
            logger.debug e.message
            logger.debug e.backtrace.inspect
            raise e
        end

        
        logger.debug { "successfully created booking: #{id}" }
        "Ok"
    end


    protected


    def swipe_occured(info)
        # Update the user details
        @last_swipe_at = Time.now.to_i
        self[:fullname] = "#{info[:firstname]} #{info[:lastname]}"
        self[:username] = info[:staff_id]
        email = nil

        if self[:username] && @ldap_creds
            email = EMAIL_CACHE[self[:username]]
            if email
                set_email(email)
                logger.debug { "email #{email} found in cache" }
            else
                # Cache username here as self[:username] might change while we
                #  looking up the previous username
                username = self[:username]

                logger.debug { "looking up email for #{username} - #{self[:fullname]}" }
                task {
                    ldap_lookup_email username
                }.then do |email|
                    if email
                        logger.debug { "email #{email} found in LDAP" }
                        EMAIL_CACHE[username] = email
                        set_email(email)
                    else
                        logger.warn "no email found in LDAP for #{username}"
                        set_email nil
                    end
                end
            end
        else
            logger.warn "no staff ID for user #{self[:fullname]}"
            set_email nil
        end
    end

    def set_email(email)
        self[:email] = email
        self[:swiped] += 1
    end

    # ====================================
    # LDAP lookup to occur in worker thread
    # ====================================
    def ldap_lookup_email(username)
        email = EMAIL_CACHE[username]
        return email if email

        ldap = Net::LDAP.new @ldap_creds
        ldap.authenticate @ldap_user[:username], @ldap_user[:password] if @ldap_user

        login_filter = Net::LDAP::Filter.eq('sAMAccountName', username)
        object_filter = Net::LDAP::Filter.eq('objectClass', '*')
        treebase = @tree_base
        search_attributes = ['mail']

        email = nil
        ldap.bind
        ldap.search({
            base: treebase,
            filter: object_filter & login_filter,
            attributes: search_attributes
        }) do |entry|
            email = get_attr(entry, 'mail')
        end

        # Returns email as a promise
        EMAIL_CACHE[username] = email
        email
    end

    def get_attr(entry, attr_name)
        if attr_name != "" && attr_name != nil
            entry[attr_name].is_a?(Array) ? entry[attr_name].first : entry[attr_name]
        end
    end
    # ====================================


    # =======================================
    # EWS Requests to occur in a worker thread
    # =======================================
    def make_google_booking(user_email: nil, subject: 'On the spot booking', room_email:, start_time:, end_time:, organizer:)
        if start_time > 1500000000000
            start_time = (start_time.to_i / 1000).to_i
            end_time = (end_time.to_i / 1000).to_i
        else
            start_time = start_time
            end_time = end_time
        end

        results = @google.create_booking({
                room_email: room_email,
                start_param: start_time,
                end_param: end_time,
                subject: subject,
                current_user: (organizer || nil),
                timezone: ENV['TIMEZONE'] || 'Sydney'
            })
        
        id = results['id']

        # Return the booking IDs
        id
    end

    def todays_bookings(events)

        logger.info "Got #{events.length} results!"
        logger.info events.to_json

        events
    end
    
    def log(data)
        STDERR.puts data
        logger.info data
        STDERR.flush
    end
end
