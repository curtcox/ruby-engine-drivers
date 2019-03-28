module Microsoft::Officenew::Events


    ##
    # For every mailbox (email) passed in, this method will grab all the bookings and, if
    # requested, return the availability of the mailboxes for some time range.
    # 
    # @param mailboxes [Array] An array of mailbox emails to pull bookings from. These are generally rooms but could be users.
    # @option options [Integer] :created_from Get all the bookings created after this seconds epoch
    # @option options [Integer] :start_param Get all the bookings that occurr between this seconds epoch and end_param
    # @option options [Integer] :end_param Get all the bookings that occurr between this seconds epoch and start_param
    # @option options [Integer] :available_from If bookings exist between this seconds epoch and available_to then the room is market as not available
    # @option options [Integer] :available_to If bookings exist between this seconds epoch and available_from then the room is market as not available
    # @option options [Array] :ignore_bookings An array of icaluids for bookings which are ignored if they fall within the available_from and to time range
    # @option options [String] :extension_name The name of the extension list to retreive in O365. This probably doesn't need to change
    # @return [Hash] A hash of room emails to availability and bookings fields, eg:
    # @example
    # An example response:
    #   {
    #     'room1@example.com' => {
    #       available: false,
    #       bookings: [
    #         {
    #           subject: 'Blah',
    #           start_epoch: 1552974994
    #           ...
    #         }, {
    #           subject: 'Foo',
    #           start_epoch: 1552816751
    #           ...
    #         }
    #       ]   
    #     },
    #     'room2@example.com' => {
    #       available: false,
    #       bookings: [{
    #         subject: 'Blah',
    #         start_epoch: 1552974994
    #       }]
    #       ...
    #     }
    #   }
    def get_bookings(mailboxes:, options:{})
        default_options = {
            created_from: nil,
            start_param: nil,
            end_param: nil,
            available_from: nil,
            available_to: nil,
            ignore_bookings: [],
            extension_name: "Com.Acaprojects.Extensions"
        }
        # Merge in our default options with those passed in
        options = options.reverse_merge(default_options)

        # We should always have an array of mailboxes
        mailboxes = Array(mailboxes)

        # We need at least one of these params
        if options[:start_param].nil? && options[:available_from].nil? && options[:created_from].nil?
            raise "either start_param, available_from or created_from is required"
        end

        # If there is no params to get bookings for, set those based on availability params
        if options[:available_from].present? && options[:start_param].nil? 
             options[:start_param] = options[:available_from]
             options[:end_param] = options[:available_to]
        end

        # If we are using created_from then we cannot use the calendarView and must use events
        endpoint = ( options[:created_from].nil? ? "calendarView" : "events" )

        # Get all of the endpoints for our bulk request
        all_endpoints = mailboxes.map do |email|
            "/users/#{email}/#{endpoint}"
        end

        # This is currently the max amount of queries per bulk request
        slice_size = 20
        responses = []
        all_endpoints.each_slice(slice_size).with_index do |endpoints, ind|
            query = {
                '$top': 10000
            }
            # Add the relevant query params
            query[:startDateTime] = graph_date(options[:start_param]) if options[:start_param]
            query[:endDateTime] = graph_date(options[:end_param]) if options[:end_param]
            query[:'$filter'] = "createdDateTime gt #{created_from}" if options[:created_from]
            query[:'$expand'] = "extensions($filter=id eq '#{options[:extension_name]}')" if options[:extension_name]

            # Make the request, check the repsonse then parse it
            bulk_response = graph_request(request_method: 'get', endpoints: endpoints, query: query, bulk: true)
            check_response(bulk_response)
            parsed_response = JSON.parse(bulk_response.body)['responses']

            # Ensure that we reaggregate the bulk requests correctly
            parsed_response.each do |res|
                local_id = res['id'].to_i
                global_id = local_id + (slice_size * ind.to_i)
                res['id'] = global_id
                responses.push(res)
            end
        end

        # Arrange our bookings by room
        bookings_by_room = {}
        responses.each_with_index do |res, i|
            bookings = res['body']['value']
            is_available = true
            # Go through each booking and extract more info from it
            bookings.each_with_index do |booking, i|
                # # Check if the bookings fall inside the availability window
                # booking = check_availability(booking, options[:available_from], options[:available_to], mailboxes[res['id']])
                # # Alias a bunch of fields we use to follow our naming convention
                # booking = alias_fields(booking)
                # # Set the attendees as internal or external and alias their fields too
                # bookings[i] = set_attendees(booking)
                # if bookings[i]['free'] == false && !options[:ignore_bookings].include?(bookings[i]['icaluid'])
                #     is_available = false
                # end


                bookings[i] = Microsoft::Officenew::Event.new(client: self, event: booking, available_to: options[:available_to], available_from: options[:available_from])
            end
            bookings_by_room[mailboxes[res['id'].to_i]] = {available: is_available, bookings: bookings}
        end
        bookings_by_room
    end
    
    
    def create_booking(mailbox:, start_param:, end_param:, options: {})
        default_options = {
            room_emails: [],
            subject: "Meeting",
            description: nil,
            organizer_name: nil,
            organizer_email: mailbox,
            attendees: [],
            recurrence_type: nil,
            recurrence_end: nil,
            is_private: false,
            timezone: 'UTC',
            extensions: {},
            location: nil
        }
        # Merge in our default options with those passed in
        options = options.reverse_merge(default_options)

        # Turn our array of room emails into an array of rooms (ControlSystems)
        rooms = room_emails.map { |r_id| Orchestrator::ControlSystem.find_by_email(r_id) }

        # Get the timezones out of the room's zone if it has any
        timezone = get_timezone(rooms[0]) if rooms.present?

        # Create the JSON body for our event
        event_json = create_event_json(
            subject: options[:subject],
            body: options[:description],
            rooms: rooms,
            start_param: start_param,
            end_param: end_param,
            timezone: (timezone || "UTC"),
            location: options[:location],
            attendees: options[:attendees],
            organizer_name: options[:organizer_name],
            organizer_email: options[:organizer_email],
            recurrence_type: options[:recurrence_type],
            recurrence_end: options[:recurrence_end],
            is_private: options[:is_private]
        )

        # Make the request and check the response
        request = graph_request(request_method: 'post', endpoint: "/v1.0/users/#{mailbox}/events", data: event_json)
        check_response(request)

    end

    def update_booking(booking_id:, mailbox:, options: {})
        default_options = {
            start_param: nil,
            end_param: nil,
            room_emails: [],
            subject: "Meeting",
            description: nil,
            organizer_name: nil,
            organizer_email: mailbox,
            attendees: [],
            recurrence_type: nil,
            recurrence_end: nil,
            is_private: false,
            timezone: 'UTC',
            extensions: {},
            location: nil
        }
        # Merge in our default options with those passed in
        options = options.reverse_merge(default_options)

        # Turn our array of room emails into an array of rooms (ControlSystems)
        rooms = room_emails.map { |r_id| Orchestrator::ControlSystem.find_by_email(r_id) }

        # Get the timezones out of the room's zone if it has any
        timezone = get_timezone(rooms[0]) if rooms.present?

        # Create the JSON body for our event
        event_json = create_event_json(
            subject: options[:subject],
            body: options[:description],
            rooms: rooms,
            start_param: options[:start_param],
            end_param: options[:end_param],
            timezone: (timezone || "UTC"),
            location: options[:location],
            attendees: options[:attendees],
            organizer_name: options[:organizer_name],
            organizer_email: options[:organizer_email],
            recurrence_type: options[:recurrence_type],
            recurrence_end: options[:recurrence_end],
            is_private: options[:is_private]
        )

        # Make the request and check the response
        request = graph_request(request_method: 'patch', endpoint: "/v1.0/users/#{mailbox}/events/#{booking_id}", data: event_json)
        check_response(request)
        request
    end

    protected

    def create_event_json(subject: nil, body: nil, start_param: nil, end_param: nil, timezone: nil, rooms: [], location: nil, attendees: nil, organizer_name: nil, organizer_email: nil, recurrence_type: nil, recurrence_end: nil, is_private: false)
        # Put the attendees into the MS Graph expeceted format
        attendees.map! do |a|
            attendee_type = ( a[:optional] ? "optional" : "required" )
            { emailAddress: { address: a[:email], name: a[:name] }, type: attendee_type }
        end

        # Add each room to the attendees array
        rooms.each do |room|
            attendees.push({ type: "resource", emailAddress: { address: room.email, name: room.name } })
        end

        # If we have rooms then build the location from that, otherwise use the passed in value
        event_location = rooms.map{ |room| room.name }.join(" and ")
        event_location = ( event_location.present? ? event_location : location )

        event_json = {}
        event_json[:subject] = subject
        event_json[:attendees] = attendees
        event_json[:sensitivity] = ( is_private ? "private" : "normal" )

        event_json[:body] = {
            contentType: "HTML",
            content: (body || "")
        }

        event_json[:start] = {
            dateTime: start_param,
            timeZone: timezone
        } if start_param

        event_json[:end] = {
            dateTime: end_param,
            timeZone: timezone
        } if end_param

        event_json[:location] = {
            displayName: location
        } if location

        event_json[:organizer] = {
            emailAddress: {
                address: organizer_email,
                name: organizer_name
            }
        } if organizer

        event[:recurrence] = {
            pattern: {
                type: recurrence_type,
                interval: 1,
                daysOfWeek: [epoch_in_timezone(start_param, timezone).strftime("%A")]
            },
            range: {
                type: 'endDate',
                startDate: epoch_in_timezone(start_param, timezone).strftime("%F"),
                endDate: epoch_in_timezone(recurrence_end, timezone).strftime("%F")
            }
        } if recurrence_type

        event_json.reject!{|k,v| v.nil?} 
    end


    def get_timezone(room)
        timezone = nil
        room.zones.each do |zone_id|
            zone = Orchestrator::Zone.find(zone_id)
            if zone.settings.key?("timezone")
                timezone = zone.settings['timezone']
            end
        end
        timezone
    end

end
