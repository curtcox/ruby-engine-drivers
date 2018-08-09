require 'active_support/time'
require 'logger'
module Microsoft
    class Error < StandardError
        class ResourceNotFound < Error; end
        class InvalidAuthenticationToken < Error; end
        class BadRequest < Error; end
        class ErrorInvalidIdMalformed < Error; end
        class ErrorAccessDenied < Error; end
    end
end

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
            service_account_password:,
            internet_proxy:nil,
            permission: 'impersonation',
            mailbox_location: 'user',
            logger: Rails.logger
        )
        @client_id = client_id
        @client_secret = client_secret
        @app_site = app_site
        @app_token_url = app_token_url
        @app_scope = app_scope
        @graph_domain = graph_domain
        @service_account_email = service_account_email
        @service_account_password = service_account_password
        @internet_proxy = internet_proxy
        @permission = permission
        @mailbox_location = mailbox_location
        @delegated = false
        oauth_options = { site: @app_site,  token_url: @app_token_url }
        oauth_options[:connection_opts] = { proxy: @internet_proxy } if @internet_proxy
        @graph_client ||= OAuth2::Client.new(
            @client_id,
            @client_secret,
            oauth_options
        )
    end 

    def graph_token
       @graph_token = @graph_client.client_credentials.get_token({
            :scope => @app_scope
        }).token
    end

    def password_graph_token
        @graph_token = @graph_client.password.get_token(
        @service_account_email,
        @service_account_password,
        {
            :scope => @app_scope
        }).token
    end

    def graph_request(request_method:, endpoint:, data:nil, query:{}, headers:nil, password:false)
        headers = Hash(headers)
        query = Hash(query)
        # Convert our request method to a symbol and our data to a JSON string
        request_method = request_method.to_sym
        data = data.to_json if !data.nil? && data.class != String

        if password
            headers['Authorization'] = "Bearer #{password_graph_token}"
        else
            headers['Authorization'] = "Bearer #{graph_token}"
        end

        # Set our unchanging headers
        headers['Content-Type'] = ENV['GRAPH_CONTENT_TYPE'] || "application/json"
        headers['Prefer'] = ENV['GRAPH_PREFER'] || 'outlook.timezone="Australia/Sydney"'

        graph_path = "#{@graph_domain}#{endpoint}"

        log_graph_request(request_method, data, query, headers, graph_path, password)


        graph_api_options = {inactivity_timeout: 25000}
        if @internet_proxy
            proxy = URI.parse(@internet_proxy)
            graph_api_options[:proxy] = { host: proxy.host, port: proxy.port }
        end

        graph_api = UV::HttpEndpoint.new(@graph_domain, graph_api_options)
        response = graph_api.__send__(request_method, path: graph_path, headers: headers, body: data, query: query)

        start_timing = Time.now.to_i
        response_value = response.value
        end_timing = Time.now.to_i
        STDERR.puts "Graph request took #{end_timing - start_timing} seconds"
        STDERR.flush
        return response_value
    end


    def bulk_graph_request(request_method:, endpoints:, data:nil, query:nil, headers:nil, password:false)
        query = Hash(query)
        headers = Hash(headers)

        if password
            headers['Authorization'] = "Bearer #{password_graph_token}"
        else
            headers['Authorization'] = "Bearer #{graph_token}"
        end

        # Set our unchanging headers
        headers['Content-Type'] = ENV['GRAPH_CONTENT_TYPE'] || "application/json"
        headers['Prefer'] = ENV['GRAPH_PREFER'] || 'outlook.timezone="Australia/Sydney"'

        graph_path = "#{@graph_domain}/v1.0/$batch"
        query_string = "?#{query.map { |k,v| "#{k}=#{v}" }.join('&')}"

        request_array = []
        endpoints.each_with_index do |endpoint, i|
            request_array.push({
                id: i,
                method: request_method.upcase,
                url: "#{endpoint}#{query_string}"
            })
        end
        bulk_data = {
            requests: request_array
        }.to_json

        graph_api_options = {inactivity_timeout: 25000, keepalive: false}

        if @internet_proxy
            proxy = URI.parse(@internet_proxy)
            graph_api_options[:proxy] = { host: proxy.host, port: proxy.port }
        end

        graph_api = UV::HttpEndpoint.new(@graph_domain, graph_api_options)
        response = graph_api.__send__('post', path: graph_path, headers: headers, body: bulk_data)

        start_timing = Time.now.to_i
        response_value = response.value
        end_timing = Time.now.to_i
        STDERR.puts "Bulk Graph request took #{end_timing - start_timing} seconds"
        STDERR.flush
        return response_value
    end


    def log_graph_request(request_method, data, query, headers, graph_path, password)
        STDERR.puts "--------------NEW GRAPH REQUEST------------"
        STDERR.puts "#{request_method} to #{graph_path}"
        STDERR.puts "Data:"
        STDERR.puts data if data
        STDERR.puts "Query:"
        STDERR.puts query if query
        STDERR.puts "Headers:"
        STDERR.puts headers if headers
        STDERR.puts "Password auth is: #{password}"
        STDERR.puts '--------------------------------------------'
        STDERR.flush
    end

    def check_response(response)
        case response.status
        when 200, 201, 204
            return
        when 400
            STDERR.puts "GOT ERROR"
            STDERR.puts response.inspect
            STDERR.flush
            if response['error']['code'] == 'ErrorInvalidIdMalformed'
                raise Microsoft::Error::ErrorInvalidIdMalformed.new(response.body)
            else
                raise Microsoft::Error::BadRequest.new(response.body)
            end
        when 401
            raise Microsoft::Error::InvalidAuthenticationToken.new(response.body)
        when 403
            raise Microsoft::Error::ErrorAccessDenied.new(response.body)
        when 404
            raise Microsoft::Error::ResourceNotFound.new(response.body)
        end
    end

    def get_users(q: nil, limit: nil)
        if q && q.include?(" ")
            queries = q.split(" ")
            filter_params = []
            queries.each do |q|
                filter_params.push("(startswith(displayName,'#{q}') or startswith(givenName,'#{q}') or startswith(surname,'#{q}') or startswith(mail,'#{q}') or startswith(userPrincipalName,'#{q}'))")
            end
            filter_param = filter_params.join(" or ")
        else
            filter_param = "startswith(displayName,'#{q}') or startswith(givenName,'#{q}') or startswith(surname,'#{q}') or startswith(mail,'#{q}') or startswith(userPrincipalName,'#{q}')" if q
        end
        query_params = {
            '$filter': filter_param,
            '$top': limit
        }.compact
        endpoint = "/v1.0/users"
        request = graph_request(request_method: 'get', endpoint: endpoint, query: query_params, password: @delegated)
        check_response(request)
        JSON.parse(request.body)['value']
    end

    def get_user(user_id:)
        endpoint = "/v1.0/users/#{user_id}"
        request = graph_request(request_method: 'get', endpoint: endpoint, password: @delegated)
        check_response(request)
        JSON.parse(request.body)
    end

    def has_user(user_id:)
        endpoint = "/v1.0/users/#{user_id}"
        request = graph_request(request_method: 'get', endpoint: endpoint, password: @delegated)
        if [200, 201, 204].include?(request.status)
            return true
        else
            return false
        end
    end

    def get_rooms(q: nil, limit: nil)
        filter_param = "startswith(name,'#{q}') or startswith(address,'#{q}')" if q
        query_params = {
            '$filter': filter_param,
            '$top': limit
        }.compact
        endpoint = "/beta/users/#{@service_account_email}/findRooms"
        request = graph_request(request_method: 'get', endpoint: endpoint, query: query_params, password: @delegated)
        check_response(request)
        room_response = JSON.parse(request.body)['value']
    end

    def get_room(room_id:)
        endpoint = "/beta/users/#{@service_account_email}/findRooms"
        request = graph_request(request_method: 'get', endpoint: endpoint, password: true)
        check_response(request)
        room_response = JSON.parse(request.body)['value']
        room_response.select! { |room| room['email'] == room_id }
    end

    def get_available_rooms(rooms:, start_param:, end_param:)
        endpoint = "/v1.0/users/#{@service_account_email}/findMeetingTimes" 
        now = Time.now
        start_ruby_param = ensure_ruby_date((start_param || now))
        end_ruby_param = ensure_ruby_date((end_param || (now + 1.hour)))
        duration_string = "PT#{end_ruby_param.to_i-start_ruby_param.to_i}S"
        start_param = start_ruby_param.utc.iso8601.split("+")[0]
        end_param = end_ruby_param.utc.iso8601.split("+")[0]

        # Add the attendees
        rooms.map!{|room|
            { 
                type: 'required',
                emailAddress: {
                    address: room[:email],
                    name: room[:name]
            }   }
        }

        time_constraint = {
            activityDomain: 'unrestricted',
            timeslots: [{
                start: {
                    DateTime: start_param,
                    TimeZone: 'UTC'
                },
                end: {
                    DateTime: end_param,
                    TimeZone: 'UTC'
                }
            }]
        }

        post_data = {
            attendees: rooms,
            timeConstraint: time_constraint,
            maxCandidates: 1000,
            returnSuggestionReasons: true,
            meetingDuration: duration_string,
            isOrganizerOptional: true


        }.to_json

        request = graph_request(request_method: 'post', endpoint: endpoint, data: post_data, password: true)
        check_response(request)
        JSON.parse(request.body)
    end

    def get_booking(booking_id:, mailbox:)
        endpoint = "/v1.0/users/#{mailbox}/events/#{booking_id}"
        request = graph_request(request_method: 'get', endpoint: endpoint, password: @delegated)
        check_response(request)
        JSON.parse(request.body)
    end

    def delete_booking(booking_id:, mailbox:)
        endpoint = "/v1.0/users/#{mailbox}/events/#{booking_id}"
        request = graph_request(request_method: 'delete', endpoint: endpoint, password: @delegated)
        check_response(request)
        200
    end


    def get_bookings_by_user(user_id:, start_param:Time.now, end_param:(Time.now + 1.week), available_from: Time.now, available_to: (Time.now + 1.hour), bulk: false, availability: true)
        # The user_ids param can be passed in as a string or array but is always worked on as an array
        user_id = Array(user_id)

        # Allow passing in epoch, time string or ruby Time class
        start_param = ensure_ruby_date(start_param).utc.iso8601.split("+")[0]
        end_param = ensure_ruby_date(end_param).utc.iso8601.split("+")[0]

        # Array of all bookings within our period
        if bulk
            recurring_bookings = bookings_request_by_users(user_id, start_param, end_param)
        else
            recurring_bookings = bookings_request_by_user(user_id, start_param, end_param)
        end

        recurring_bookings.each do |u_id, bookings|
            is_available = true
            bookings.each_with_index do |booking, i|
                bookings[i] = extract_booking_data(booking, available_from, end_param)
                if bookings[i]['free'] == false
                    is_available = false
                end
            end
            recurring_bookings[u_id] = {available: is_available, bookings: bookings}
        end

        if bulk
            return recurring_bookings
        else
            if availability
                return recurring_bookings[user_id[0]]
            else
                return recurring_bookings[user_id[0]][:bookings]
            end
        end
    end

    def extract_booking_data(booking, start_param, end_param)
        # Create time objects of the start and end for easier use
        booking_start = ActiveSupport::TimeZone.new(booking['start']['timeZone']).parse(booking['start']['dateTime'])
        booking_end = ActiveSupport::TimeZone.new(booking['end']['timeZone']).parse(booking['end']['dateTime'])

        # Check if this means the room is unavailable
        booking_overlaps_start = booking_start < start_param && booking_end > start_param
        booking_in_between = booking_start >= start_param && booking_end <= end_param
        booking_overlaps_end = booking_start < end_param && booking_end > end_param
        if booking_overlaps_start || booking_in_between || booking_overlaps_end
            booking['free'] = false
        else
            booking['free'] = true
        end

        # Grab the start and end in the right format for the frontend
        booking['Start'] = booking_start.utc.iso8601
        booking['End'] = booking_end.utc.iso8601
        booking['start_epoch'] = booking_start.to_i
        booking['end_epoch'] = booking_end.to_i

        # Get some data about the booking
        booking['title'] = booking['subject']
        booking['booking_id'] = booking['id']

        # Format the attendees and save the old format
        new_attendees = []
        booking['attendees'].each do |attendee|
            if attendee['type'] == 'resource'
                booking['room_id'] = attendee['emailAddress']['address'].downcase
            else
                new_attendees.push({
                    email: attendee['emailAddress']['address'],
                    name: attendee['emailAddress']['name']
                })
            end
        end
        booking['old_attendees'] = booking['attendees']
        booking['attendees'] = new_attendees

        # Get the organiser and location data
        booking['organizer'] = { name: booking['organizer']['emailAddress']['name'], email: booking['organizer']['emailAddress']['address']}
        if !booking.key?('room_id') && booking['locations'] && !booking['locations'].empty? && booking['locations'][0]['uniqueId']
            booking['room_id'] = booking['locations'][0]['uniqueId'].downcase 
        end
        if !booking['location']['displayName'].nil? && !booking['location']['displayName'].empty?
            booking['room_name'] = booking['location']['displayName']
        end

        booking
    end

    def bookings_request_by_user(user_id, start_param=Time.now, end_param=(Time.now + 1.week))
        if user_id.class == Array
            user_id = user_id[0]
        end
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

        recurring_response = graph_request(request_method: 'get', endpoint: recurring_endpoint, query: query_hash, password: @delegated)
        check_response(recurring_response)
        recurring_bookings = {}
        recurring_bookings[user_id] = JSON.parse(recurring_response.body)['value']
        recurring_bookings
    end

    def bookings_request_by_users(user_ids, start_param=Time.now, end_param=(Time.now + 1.week))
        # Allow passing in epoch, time string or ruby Time class
        start_param = ensure_ruby_date(start_param).iso8601.split("+")[0]
        end_param = ensure_ruby_date(end_param).iso8601.split("+")[0]

        endpoints = user_ids.map do |email|
            "/users/#{email}/calendarView"
        end
        query = {
            '$top': 200,
            startDateTime: start_param,
            endDateTime: end_param,
        }
        bulk_response = bulk_graph_request(request_method: 'get', endpoints: endpoints, query: query )

        check_response(bulk_response)
        responses = JSON.parse(bulk_response.body)['responses']
        recurring_bookings = {}
        responses.each_with_index do |res, i|
            recurring_bookings[user_ids[res['id'].to_i]] = res['body']['value']
        end
        recurring_bookings
    end

    def get_bookings_by_room(room_id:, start_param:Time.now, end_param:(Time.now + 1.week))
        return get_bookings_by_user(user_id: room_id, start_param: start_param, end_param: end_param)
    end


    def create_booking(room_id:, start_param:, end_param:, subject:, description:nil, current_user:, attendees: nil, recurrence: nil, is_private: false, timezone:'Sydney')
        description = String(description)
        attendees = Array(attendees)

        # Get our room
        room = Orchestrator::ControlSystem.find(room_id)

        if @mailbox_location == 'room' || current_user.nil?
            endpoint = "/v1.0/users/#{room.email}/events"
        elsif @mailbox_location == 'user'
            endpoint = "/v1.0/users/#{current_user[:email]}/events"
        end

        # Ensure our start and end params are Ruby dates and format them in Graph format
        start_object = ensure_ruby_date(start_param).in_time_zone(timezone)
        end_object = ensure_ruby_date(end_param).in_time_zone(timezone)
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
        if current_user
            attendees.push({
                emailAddress: {
                    address: current_user[:email],
                    name: current_user[:name]
                }
            })
        end

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
            attendees: attendees
        }

        if current_user
            event[:organizer] = {
                emailAddress: {
                    address: current_user.email,
                    name: current_user.name
                }
            }
        else
            event[:organizer] = {
                emailAddress: {
                    address: room.email,
                    name: room.name
                }
            }
        end
        
        if recurrence
            event[:recurrence] = {
                pattern: {
                    type: recurrence,
                    interval: 1,
                    daysOfWeek: [start_object.strftime("%A")]
                },
                range: {
                    type: 'noEnd',
                    startDate: start_object.strftime("%F")
                }
            }
        end

        if is_private
            event[:sensitivity] = 'private'
        end

        event = event.to_json

        request = graph_request(request_method: 'post', endpoint: endpoint, data: event, password: @delegated)

        check_response(request)

        response = JSON.parse(request.body)
    end

    def update_booking(booking_id:, room_id:, start_param:nil, end_param:nil, subject:nil, description:nil, attendees:nil, timezone:'Sydney')
        # We will always need a room and endpoint passed in
        room = Orchestrator::ControlSystem.find_by_email(room_id)
        endpoint = "/v1.0/users/#{room.email}/events/#{booking_id}"
        STDERR.puts "ENDPOINT IS"
        STDERR.puts endpoint
        STDERR.flush

        
        start_object = ensure_ruby_date(start_param).in_time_zone(timezone)
        end_object = ensure_ruby_date(end_param).in_time_zone(timezone)
        start_param = ensure_ruby_date(start_param).in_time_zone(timezone).iso8601.split("+")[0]
        end_param = ensure_ruby_date(end_param).in_time_zone(timezone).iso8601.split("+")[0]
        
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

        request = graph_request(request_method: 'patch', endpoint: endpoint, data: event.to_json, password: @delegated)
        check_response(request)
        response = JSON.parse(request.body)['value']
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
