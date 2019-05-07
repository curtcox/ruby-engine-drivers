

module IBM; end
module IBM::Domino; end

# Documentation: https://aca.im/driver_docs/IBM/Domino%20Freebusy%20Service.pdf
#  also https://www-10.lotus.com/ldd/ddwiki.nsf/xpAPIViewer.xsp?lookupName=IBM+Domino+Access+Services+9.0.1#action=openDocument&res_title=Calendar_events_GET&content=apicontent
#  also https://www-10.lotus.com/ldd/ddwiki.nsf/xpAPIViewer.xsp?lookupName=IBM+Domino+Access+Services+9.0.1#action=openDocument&res_title=JSON_representation_of_an_event_das901&content=apicontent

class IBM::Domino::NotesCalendar
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    implements :service
    descriptive_name 'IBM Notes Calendar'
    generic_name :Calendar

    default_settings({
        'timezone'  => 'Singapore',
        'database'  => 'room-name.nsf',
        'username'  => 'username',
        '$password' => 'password'
    })

    def on_load
        on_update
    end

    def on_update
        @timezone = setting(:timezone)
        @username = setting(:username)
        @password = setting(:password)
        @database = setting(:database)
    end

    DECODE_OPTIONS = {
        symbolize_names: true
    }.freeze


    # =================
    # Free Busy Service
    # =================
    def free_rooms(building:, starting:, ending:, capacity: nil, timezone: @timezone)
        starting, ending = get_time_range(starting, ending, timezone)
        params = {
            :site => building,
            :start => starting.utc.iso8601,
            :end => ending.utc.iso8601
        }
        params[:capacity] = capacity.to_i if capacity

        get('/api/freebusy/freerooms', query: params) do |data|
            return :retry unless data.status == 200
            JSON.parse(data.body, DECODE_OPTIONS)[:rooms]
        end
    end

    def user_busy(email:, starting: nil, ending: nil, days: nil, timezone: @timezone)
        since, before = get_time_range(starting, ending, timezone)
        params = {
            name: email,
            since: since.utc.iso8601
        }
        if days
            params[:days] = days
        else
            params[:before] = before.utc.iso8601
        end

        get('/api/freebusy/busytime', query: params) do |data|
            return :retry unless data.status == 200
            times = JSON.parse(data.body, DECODE_OPTIONS)[:busyTimes]
            times.collect do |period|
                s = period[:start]
                e = period[:end]
                {
                    starting: Time.iso8601("#{s[:date]}T#{s[:time]}Z"),
                    ending: Time.iso8601("#{e[:date]}T#{e[:time]}Z")
                }
            end
        end
    end

    def directories
        get('/api/freebusy/directories') do |data|
            return :retry unless data.status == 200
            JSON.parse(data.body, DECODE_OPTIONS)
        end
    end

    def sites(directory)
        get("/api/freebusy/sites/#{directory}") do |data|
            return :retry unless data.status == 200
            JSON.parse(data.body, DECODE_OPTIONS)
        end
    end

    # =====================
    # Domino Access Service
    # =====================
    def bookings(starting: nil, ending: nil, timezone: @timezone, count: 100, start: 0, fields: nil, **opts)
        since, before = get_time_range(starting, ending, timezone)
        query = {
            start: start,
            count: count,
            since: since.utc.iso8601,
            before: before.utc.iso8601,
            headers: {
                authorization: [@username, @password]
            }
        }
        query[:fields] = Array(fields).join(',') if fields.present?
        get("/mail/#{@database}/api/calendar/events", query: query) do |data|
            return :retry unless data.status == 200
            parse(JSON.parse(data.body, DECODE_OPTIONS))
        end
    end

    def cancel_booking(id:, recurrenceId: nil, email_attendees: false, **opts)
        query = {}
        query[:workflow] = false unless email_attendees

        uri = if recurrenceId
            "/mail/#{@database}/api/calendar/events/#{id}/#{recurrenceId}"
        else
            "/mail/#{@database}/api/calendar/events/#{id}"
        end

        delete(uri, query: query) do |data|
            logger.warn "unable to delete meeting #{id} as it could not be found" if data.status == 404
            :success
        end
    end

    def create_booking(starting:, ending:, summary:, location: nil, description: nil, organizer: nil, email_attendees: false, attendees: [], timezone: @timezone, **opts)
        event = {
            :summary => summary,
            :class => :public,
            :start => to_date(starting),
            :end => to_date(ending)
        }

        event[:location] = location if location
        event[:description] = description if description

        # The value can be either "application/json" or "text/calendar"
        headers = {
            'content-type' => 'application/json'
        }

        # If workflow=false, the service doesn't send out any invitations
        query = {}
        query[:workflow] = false unless email_attendees

        event[:attendees] = Array(attendees).collect do |attendee|
            {
                role: "req-participant",
                email: attendee
            }
        end

        if organizer
            event[:organizer] = {
                email: organizer
            }

            # Chair has permissions to edit the event
            event[:attendees].push({
                role: "chair",
                email: organizer
            })
        end

        post("/mail/#{@database}/api/calendar/events", {
            query: query,
            headers: headers,
            body: event.to_json
        }) do |data|
            return parse(JSON.parse(data.body, DECODE_OPTIONS)) if data.status == 201
            :retry
        end
    end


    protected


    def get_time_range(starting, ending, timezone)
        return [starting, ending] if starting.is_a?(Time)

        Time.zone = timezone
        start = starting.nil? ? Time.zone.today.to_time : Time.zone.parse(starting)
        fin = ending.nil? ? Time.zone.tomorrow.to_time : Time.zone.parse(ending)
        [start, fin]
    end

    def to_date(time)
        utctime = time.getutc
        {
            date: utctime.strftime("%Y-%m-%d"),
            time: utctime.strftime("%H-%M-%S"),
            utc: true
        }
    end

    TIMEZONE_MAP = {
        'eastern' => 'Eastern Time (US & Canada)'
    }

    def parse(response)
        events = response[:events]
        Array(events).collect do |event|
            ev = {
                resource: event[:href],
                id: event[:id],
                summary: event[:summary],
                location: event[:location]
            }

            ev[:recurrenceId] = event[:recurrenceId] if event[:recurrenceId]

            # Generate ruby time objects for easy manipulation
            time = event[:start]
            if time[:utc]
                ev[:starting] = Time.iso8601("#{time[:date]}T#{time[:time]}Z")
                time = event[:end]
                ev[:ending] = Time.iso8601("#{time[:date]}T#{time[:time]}Z")
            else
                tz = TIMEZONE_MAP[time[:tzid].downcase]
                if tz
                    Time.zone = tz
                else
                    Time.zone = "UTC"
                    logger.warn "Could not find timezone #{time[:tzid]}"
                end
                ev[:starting] = Time.zone.iso8601("#{time[:date]}T#{time[:time]}")
                time = event[:end]
                ev[:ending] = Time.zone.iso8601("#{time[:date]}T#{time[:time]}")
            end

            ev[:organizer] = if event[:organizer]
                # Domino returns: "Darius Servino Oco\/SG\/GTS\/PwC"
                event[:organizer][:displayName].split('/')[0]
            elsif event[:"x-lotus-organizer"]
                # Domino returns: "CN=Darius Servino Oco\/OU=SG\/OU=GTS\/O=PwC"
                event[:"x-lotus-organizer"][:data].split("CN=")[1]&.split('/')[0]
            end

            ev
        end
    end
end
