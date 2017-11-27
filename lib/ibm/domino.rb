require 'active_support/time'
module IBM; end

class IBM::Domino
    def initialize(
            username:,
            password:,
            auth_hash:,
            domain:,
            timezone:
        )
        @domain = domain
        @timeone = timezone
        @headers = {
            'Authorization' => "Basic #{auth_hash}",
            'Content-Type' => 'application/json'
        }
        @domino_api = UV::HttpEndpoint.new(@domain, {inactivity_timeout: 25000})
    end

    def domino_request(request_method, endpoint, data = nil, query = {}, headers = {})
        # Convert our request method to a symbol and our data to a JSON string
        request_method = request_method.to_sym
        data = data.to_json if !data.nil? && data.class != String

        @headers.merge(headers) if headers  

        domino_path = "#{ENV['DOMINO_DOMAIN']}#{endpoint}"
        response = @domino_api.__send__(request_method, path: domino_path, headers: @headers, body: data, query: query)
    end

    def get_free_rooms(starting, ending)
        starting, ending = convert_to_datetime(starting, ending)        
        starting, ending = get_time_range(starting, ending, @timezone)

        req_params = {
            :site => ENV["DOMINO_SITE"],
            :start => to_ibm_date(starting),
            :end => to_ibm_date(ending),
            :capacity => 1
        }

        res = domino_request('get','/api/freebusy/freerooms', nil, req_params).value
        domino_emails = JSON.parse(res.body)['rooms']
    end



    def get_bookings(room_id, starting, ending, days=nil)
        room = Orchestrator::ControlSystem.find(room_id)
        Rails.logger.info "Getting bookings for #{room.name}"
        database = room.settings['database']
        starting, ending = convert_to_datetime(starting, ending)
        # Set count to max
        query = {
            count: 100
        }

        # If we have a range use it
        if starting
            query[:since] = to_ibm_date(starting)
            query[:before] = to_ibm_date(ending)
        end

	Rails.logger.info "Getting bookings for"
	Rails.logger.info "/#{database}/api/calendar/events"

        # Get our bookings 
        response = domino_request('get', "/#{database}/api/calendar/events", nil, query).value
        domino_bookings = JSON.parse(response.body)['events']

        # Grab the attendee for each booking
        bookings = []
	if response.status == 200 && response.body.nil?
	    Rails.logger.info "Got empty response"
	    domino_bookings = []
	end
        domino_bookings.each{ |booking|
            bookings.push(get_attendees(booking, database))
        }
        bookings
    end


    def create_booking(starting:, ending:, room:, summary:, description: nil, organizer:, attendees: [], timezone: @timezone, **opts)
        starting, ending = convert_to_datetime(starting, ending)        
        event = {
            :summary => summary,
            :class => :public,
            :start => to_utc_date(starting),
            :end => to_utc_date(ending)
        }

        event[:description] = description if description


        event[:attendees] = Array(attendees).collect do |attendee|
            {
                role: "req-participant",
                status: "needs-action",
                rsvp: true,
                displayName: attendee[:name],
                email: attendee[:email]
            }
        end

        event[:organizer] = {
            email: organizer[:email],
            displayName: organizer[:name]
        }

        # If there are attendees add the service account
        event[:attendees].push({
             "role":"chair",
             "status":"accepted",
             "rsvp":false,
             "displayName":"OTS Test1 Project SG/SG/R&R/PwC",
             "email":"ots.test1.project.sg@sg.pwc.com"
        }) if attendees    

        request = domino_request('post', "/#{room}/api/calendar/events", {events: [event]}).value
        JSON.parse(request.body)['events'][0]
    end

    def delete_booking(room, id)
        request = domino_request('delete', "/#{room}/api/calendar/events/#{id}").value.status
    end


    def edit_booking(id, starting:, ending:, room:, summary:, description: nil, organizer:, attendees: [], timezone: @timezone, **opts)
        starting, ending = convert_to_datetime(starting, ending)       
        event = {
            :summary => summary,
            :class => :public,
            :start => to_utc_date(starting),
            :end => to_utc_date(ending)
        }

        query = {}

        if description
            event[:description] = description
        else
            query[:literally] = true
        end


        event[:attendees] = Array(attendees).collect do |attendee|
            {
                role: "req-participant",
                status: "needs-action",
                rsvp: true,
                displayName: attendee[:name],
                email: attendee[:email]
            }
        end

        event[:organizer] = {
            email: organizer[:email],
            displayName: organizer[:name]
        }

        # If there are attendees add the service account
        event[:attendees].push({
             "role":"chair",
             "status":"accepted",
             "rsvp":false,
             "displayName":"OTS Test1 Project SG/SG/R&R/PwC",
             "email":"ots.test1.project.sg@sg.pwc.com"
        }) if attendees    

        request = domino_request('put', "/#{room}/api/calendar/events/#{id}", {events: [event]}, query).value
        request.status
    end

    def get_attendees(booking, database)
        path = "#{@domain}/#{database}/api/calendar/events/#{booking['id']}"
        booking_request = @domino_api.get(path: path, headers: @headers).value
        booking_response = JSON.parse(booking_request.body)['events'][0]
        if booking_response['attendees']
            attendees = booking_response['attendees'].dup 
            attendees.map!{ |attendee|
                {
                    name: attendee['displayName'],
                    email: attendee['email']
                }
            }
            booking_response['attendees'] = attendees
        end
        if booking_response['organizer']
            organizer = booking_response['organizer'].dup 
            organizer = 
            {
                name: organizer['displayName'],
                email: organizer['email']
            }            
            booking_response['organizer'] = organizer
        end
        booking_response
    end

    def to_ibm_date(time)
        time.strftime("%Y-%m-%dT%H:%M:%SZ")
    end

    def convert_to_datetime(starting, ending)
        if !(starting.class == Time)
            if string_is_digits(starting)

                # Convert to an integer
                starting = starting.to_i
                ending = ending.to_i

                # If JavaScript epoch remove milliseconds
                if starting.to_s.length == 13
                    starting /= 1000
                    ending /= 1000
                end

                # Convert to datetimes
                starting = Time.at(starting)
                ending = Time.at(ending)               
            else
                starting = Time.parse(starting)
                ending = Time.parse(ending)                    
            end
        end
        return starting, ending
    end


    def string_is_digits(string)
        string.scan(/\D/).empty?
    end

    def to_utc_date(time)
        utctime = time.getutc
        {
            date: utctime.strftime("%Y-%m-%d"),
            time: utctime.strftime("%H:%M:%S"),
            utc: true
        }
    end

    def get_time_range(starting, ending, timezone)
        return [starting, ending] if starting.is_a?(Time)

        Time.zone = timezone
        start = starting.nil? ? Time.zone.today.to_time : Time.zone.parse(starting)
        fin = ending.nil? ? Time.zone.tomorrow.to_time : Time.zone.parse(ending)
        [start, fin]
    end

end
