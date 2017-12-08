# Reference: https://www.ibm.com/developerworks/lotus/library/ls-Domino_URL_cheat_sheet/

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

    def domino_request(request_method, endpoint, data = nil, query = {}, headers = {}, full_path = nil)
        # Convert our request method to a symbol and our data to a JSON string
        request_method = request_method.to_sym
        data = data.to_json if !data.nil? && data.class != String

        @headers.merge(headers) if headers
        
        if full_path
            if full_path.include?('/api/calendar/events')
                uri = URI.parse(full_path)
            else
                uri = URI.parse(full_path + '/api/calendar/events')
            end  
            domino_api = UV::HttpEndpoint.new("https://#{uri.host}", {inactivity_timeout: 25000})
            domino_path = uri.to_s
        elsif request_method == :post
            domino_api = UV::HttpEndpoint.new(ENV['DOMINO_CREATE_DOMAIN'], {inactivity_timeout: 25000})
            domino_path = "#{ENV['DOMINO_CREATE_DOMAIN']}#{endpoint}"
        else
            domino_api = @domino_api
            domino_path = "#{ENV['DOMINO_DOMAIN']}#{endpoint}"
        end

        response = domino_api.__send__(request_method, path: domino_path, headers: @headers, body: data, query: query)
    end

    def get_free_rooms(starting, ending)
        starting, ending = convert_to_datetime(starting, ending)        
        # starting, ending = get_time_range(starting, ending, @timezone)

        starting = starting.utc
        ending = ending.utc

        req_params = {
            :site => ENV["DOMINO_SITE"],
            :start => to_ibm_date(starting),
            :end => to_ibm_date(ending),
            :capacity => 1
        }

        res = domino_request('get','/api/freebusy/freerooms', nil, req_params).value
        domino_emails = JSON.parse(res.body)['rooms']
    end

    def get_users_bookings(database,  date=Time.now.tomorrow.midnight)
        # Make date a date object from epoch or parsed text
        date = convert_to_simpledate(date)

        starting = to_ibm_date(date.yesterday)
        ending = to_ibm_date(date)

        query = {
            before: ending,
            since: starting
        }

        request = domino_request('get', nil, nil, query, nil, database).value
        if [200,201,204].include?(request.status) 
            if request.body != ''
                events = JSON.parse(request.body)['events']
            else
                events = []
            end
        else
            return nil
        end
        full_events = []
        events.each{|event|
            full_event = get_attendees(database + '/api/calendar/events/' + event['id'])
            full_events.push(full_event)
        }
        full_events
    end

    def get_bookings(room_id, date=Time.now.tomorrow.midnight)
        room = Orchestrator::ControlSystem.find(room_id)
        room_name = room.settings['name']

        # The domino API takes a StartKey and UntilKey
        # We will only ever need one days worth of bookings
        # If startkey = 2017-11-29 and untilkey = 2017-11-30
        # Then all bookings on the 30th (the day of the untilkey) are returned

        # Make date a date object from epoch or parsed text
        date = convert_to_simpledate(date)

        starting = date.yesterday.strftime("%Y%m%d")
        ending = date.strftime("%Y%m%d")

        # Set count to max
        query = {
            StartKey: starting,
            UntilKey: ending,
            KeyType: 'time',
            ReadViewEntries: nil,
            OutputFormat: 'JSON'
        }

        # Get our bookings 
        request = domino_request('get', "/RRDB.nsf/93FDE1776546DEEB482581E7000B27FF", nil, query)
        response = request.value

        # Go through the returned bookings and add to output array
        rooms_bookings = []
        bookings = JSON.parse(response.body)['viewentry'] || []
        bookings.each{ |booking|
            domino_room_name = booking['entrydata'][2]['text']['0'].split('/')[0]
            if room_name == domino_room_name
                new_booking = {
                    start: Time.parse(booking['entrydata'][0]['datetime']['0']).to_i,
                    end: Time.parse(booking['entrydata'][1]['datetime']['0']).to_i,
                    summary: booking['entrydata'][5]['text']['0'],
                    organizer: booking['entrydata'][3]['text']['0']
                }
                rooms_bookings.push(new_booking)
            end
        }
        rooms_bookings
    end


    def create_booking(current_user:, starting:, ending:, database:, room_id:, summary:, description: nil, organizer:, attendees: [], timezone: @timezone, **opts)
        room = Orchestrator::ControlSystem.find(room_id)
        starting, ending = convert_to_datetime(starting, ending)        
        event = {
            :summary => summary,
            :class => :public,
            :start => to_utc_date(starting),
            :end => to_utc_date(ending)
        }

        event[:description] = description if description


        event[:attendees] = Array(attendees).collect do |attendee|
            out_attendee = {
                role: "req-participant",
                status: "needs-action",
                rsvp: true,
                email: attendee[:email]
            }
            out_attendee[:displayName] = attendee[:name] if attendee[:name]
            out_attendee
        end

        # Set the current user as orgaqnizer and chair if no organizer passed in
        if organizer
            event[:organizer] = {
                email: organizer[:email]
            }
            event[:organizer][:displayName] = organizer[:name] if organizer[:name]

            event[:attendees].push({
                 "role":"chair",
                 "status":"accepted",
                 "rsvp":false,
                 "email": organizer[:email]
            })
        else
            event[:organizer] = {
                email: current_user.email
            }
            event[:attendees].push({
                 "role":"chair",
                 "status":"accepted",
                 "rsvp":false,
                 "email": current_user.email
            })
        end

        # Add the room as an attendee
        event[:attendees].push({
             "role":"chair",
             "status":"accepted",
             "rsvp":false,
             "userType":"room",
             "email": room.email
        })


        request = domino_request('post', nil, {events: [event]}, nil, nil, database).value
        request
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

    def get_attendees(path)
        booking_request = domino_request('get',nil,nil,nil,nil,path).value
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
        booking_response['start'] = Time.parse(booking_response['start']['date']+'T'+booking_response['start']['time']+'+0800').utc.to_i
        booking_response['end'] = Time.parse(booking_response['end']['date']+'T'+booking_response['end']['time']+'+0800').utc.to_i
        booking_response
    end

    def to_ibm_date(time)
        time.strftime("%Y-%m-%dT%H:%M:%SZ")
    end

    def convert_to_simpledate(date) 
        if !(date.class == Time)
            if string_is_digits(date)

                # Convert to an integer
                date = date.to_i

                # If JavaScript epoch remove milliseconds
                if starting.to_s.length == 13
                    starting /= 1000
                    ending /= 1000
                end

                # Convert to datetimes
                date = Time.at(date)           
            else
                date = Time.parse(date)                
            end
        end
        return date
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
        string = string.to_s
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
