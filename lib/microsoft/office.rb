require 'active_support/time'
require 'logger'
module Microsoft; end

class Microsoft::Office
    TIMEZONE_MAPPING = {
        "Sydney": "AUS Eastern Standard Time"
    }
    def initialize(
            client_id:,
            client_secret:,
            app_site:,
            app_token_url:,
            app_scope:,
            graph_domain:,
            service_account_email:,
            logger: Rails.logger
        )
        @client_id = client_id
        @client_secret = client_secret
        @app_site = app_site
        @app_token_url = app_token_url
        @app_scope = app_scope
        @graph_domain = graph_domain
        @service_account_email = service_account_email
        @graph_client ||= OAuth2::Client.new(
            @client_id,
            @client_secret,
            {:site => @app_site, :token_url => @app_token_url}
        )
    end 

    def graph_token
       @graph_token ||= @graph_client.client_credentials.get_token({
            :scope => @app_scope
        }).token
    end

    def graph_request(request_method, endpoint, data = nil, query = {}, headers = {})

        # Convert our request method to a symbol and our data to a JSON string
        request_method = request_method.to_sym
        data = data.to_json if !data.nil? && data.class != String

        # Set our unchanging headers
        headers['Authorization'] = "Bearer #{graph_token}"
        headers['Content-Type'] = ENV['GRAPH_CONTENT_TYPE'] || "application/json"
        headers['Prefer'] = ENV['GRAPH_PREFER'] || 'outlook.timezone="Australia/Sydney"'

        graph_path = "#{@graph_domain}#{endpoint}"

        log_graph_request(request_method, data, query, headers, graph_path)

        graph_api = UV::HttpEndpoint.new(@graph_domain, {inactivity_timeout: 25000})
        response = graph_api.__send__(request_method, path: graph_path, headers: headers, body: data, query: query)
    end

    def log_graph_request(request_method, data, query, headers, graph_path)
        STDERR.puts "--------------NEW GRAPH REQUEST------------"
        STDERR.puts "#{request_method} to #{graph_path}"
        STDERR.puts data if data
        STDERR.puts query if query
        STDERR.puts headers
        STDERR.puts '--------------------------------------------'
        STDERR.flush
    end


    def get_users
        endpoint = "/v1.0/users"
        user_response = JSON.parse(graph_request('get', endpoint).value.body)['value']
    end

    def get_user(user_id)
        endpoint = "/v1.0/users/#{user_id}"
        user_response = JSON.parse(graph_request('get', endpoint).value.body)['value']
    end

    def get_rooms
        endpoint = "/beta/users/#{@service_account_email}/findRooms"
        room_response = JSON.parse(graph_request('get', endpoint).value.body)['value']
    end

    def get_room(room_id)
        endpoint = "/beta/users/#{@service_account_email}/findRooms"
        room_response = JSON.parse(graph_request('get', endpoint).value.body)['value']
        room_response.select! { |room| room['email'] == room_id }
    end

    def get_bookings_by_user(user_id, start_param=Time.now, end_param=(Time.now + 1.week))
        # Allow passing in epoch, time string or ruby Time class
        start_param = ensure_ruby_date(start_param).iso8601.split("+")[0]
        end_param = ensure_ruby_date(end_param).iso8601.split("+")[0]

        # Array of all bookings within our period
        recurring_bookings = get_recurring_bookings_by_user(user_id, start_param, end_param)

        endpoint = "/v1.0/users/#{user_id}/events"
        
        query_hash = {}
        query_hash['$top'] = "200"

        # Build our query to only get bookings within our datetimes
        if not start_param.nil?
            query_hash['$filter'.to_sym] = "(Start/DateTime le '#{start_param}' and End/DateTime ge '#{start_param}') or (Start/DateTime ge '#{start_param}' and Start/DateTime le '#{end_param}')"
        end

        bookings_response = graph_request('get', endpoint, nil, query_hash).value
        bookings = JSON.parse(bookings_response.body)['value']
        bookings.concat recurring_bookings
    end

    def get_recurring_bookings_by_user(user_id, start_param=Time.now, end_param=(Time.now + 1.week))
        # Allow passing in epoch, time string or ruby Time class
        start_param = ensure_ruby_date(start_param).iso8601.split("+")[0]
        end_param = ensure_ruby_date(end_param).iso8601.split("+")[0]

        recurring_endpoint = "/v1.0/users/#{user_id}/calendarView"

        # Build our query to only get bookings within our datetimes
        query_hash = {}
        query_hash['$top'] = "200"

        if not start_param.nil?
            query_hash['startDateTime'] = start_param
            query_hash['endDateTime'] = end_param
        end

        recurring_response = graph_request('get', recurring_endpoint, nil, query_hash).value
        recurring_bookings = JSON.parse(recurring_response.body)['value']
    end

    def get_bookings_by_room(room_id, start_param=Time.now, end_param=(Time.now + 1.week))
        return get_bookings_by_user(room_id, start_param, end_param)
    end


    def create_booking(room_id:, start_param:, end_param:, subject:, description:nil, current_user:, attendees: nil, timezone:'Sydney')
        description = String(description)
        attendees = Array(attendees)

        # Get our room
        room = Orchestrator::ControlSystem.find(room_id)

        # Set our endpoint with the email
        endpoint = "/v1.0/users/#{room.email}/events"

        # Ensure our start and end params are Ruby dates and format them in Graph format
        start_param = ensure_ruby_date(start_param).in_time_zone(timezone).iso8601.split("+")[0]
        end_param = ensure_ruby_date(end_param).in_time_zone(timezone).iso8601.split("+")[0]


        # Add the attendees
        attendees.map!{|a|
            { emailAddress: {
                    address: a[:email],
                    name: a[:name]
            }   }
        }

        # Add the room as an attendee
        attendees.push({
            type: "resource",
            emailAddress: {
                address: room.email,
                name: room.name
            }
        })

        # Add the current user as an attendee
        attendees.push({
            emailAddress: {
                address: current_user.email,
                name: current_user.name
            }
        })

        # Create our event which will eventually be stringified
        event = {
            subject: subject,
            body: {
                contentType: 'html',
                content: description
            },
            start: {
                dateTime: start_param,
                timeZone: TIMEZONE_MAPPING[timezone.to_sym]
            },
            end: {
                dateTime: end_param,
                timeZone: TIMEZONE_MAPPING[timezone.to_sym]
            },
            location: {
                displayName: room.name,
                locationEmailAddress: room.email
            },
            isOrganizer: false,
            organizer: {
                emailAddress: {
                    address: current_user.email,
                    name: current_user.name
                }
            },
            attendees: attendees
        }.to_json

        response = JSON.parse(graph_request('post', endpoint, event).value.body)['value']
    end

    def update_booking(booking_id:, room_id:, start_param:nil, end_param:nil, subject:nil, description:nil, attendees:nil, timezone:'Sydney')
        # We will always need a room and endpoint passed in
        room = Orchestrator::ControlSystem.find(room_id)
        endpoint = "/v1.0/users/#{room.email}/events/#{booking_id}"
        event = {}
        event[:subject] = subject if subject

        event[:start] = {
            dateTime: start_param,
            timeZone: TIMEZONE_MAPPING[timezone.to_sym]
        } if start_param

        event[:end] = {
            dateTime: end_param,
            timeZone: TIMEZONE_MAPPING[timezone.to_sym]
        } if end_param

        event[:body] = {
            contentType: 'html',
            content: description
        } if description

        # Let's assume that the request has the current user and room as an attendee already
        event[:attendees] = attendees.map{|a|
            { emailAddress: {
                    address: a[:email],
                    name: a[:name]
            }   }
        } if attendees

        response = JSON.parse(graph_request('patch', endpoint, event).to_json.value.body)['value']
    end

    # Takes a date of any kind (epoch, string, time object) and returns a time object
    def ensure_ruby_date(date) 
        if !(date.class == Time || date.class == DateTime)
            if string_is_digits(date)

                # Convert to an integer
                date = date.to_i

                # If JavaScript epoch remove milliseconds
                if date.to_s.length == 13
                    date /= 1000
                end

                # Convert to datetimes
                date = Time.at(date)           
            else
                date = Time.parse(date)                
            end
        end
        return date
    end

    # Returns true if a string is all digits (used to check for an epoch)
    def string_is_digits(string)
        string = string.to_s
        string.scan(/\D/).empty?
    end

end
