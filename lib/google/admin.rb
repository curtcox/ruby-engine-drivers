require 'active_support/time'
require 'logger'
require 'googleauth'
require 'google/apis/admin_directory_v1'
require 'google/apis/calendar_v3'

# # Define our errors
# module Google
#     class Error < StandardError
#         class ResourceNotFound < Error; end
#         class InvalidAuthenticationToken < Error; end
#         class BadRequest < Error; end
#         class ErrorInvalidIdMalformed < Error; end
#         class ErrorAccessDenied < Error; end
#     end
# end

class Google::Admin
    TIMEZONE_MAPPING = {
        "Sydney": "AUS Eastern Standard Time"
    }
    def initialize(
            json_file_location: nil,
            scopes: nil,
            admin_email:,
            domain:,
            logger: Rails.logger
        )
        @json_file_location = json_file_location || '/home/aca-apps/ruby-engine-app/keys.json'
        @scopes = scopes || [ 'https://www.googleapis.com/auth/calendar', 'https://www.googleapis.com/auth/admin.directory.user']
        @admin_email = admin_email
        @domain = domain
        @authorization = Google::Auth.get_application_default(scopes)

        admin_api = Google::Apis::AdminDirectoryV1
        @admin = admin_api::DirectoryService.new
        @authorization.sub = @admin_email
        @admin.authorization = @authorization

        calendar_api = Google::Apis::CalendarV3
        @calendar = calendar_api::CalendarService.new
        @calendar.authorization = authorization
    end 

    def get_users(q: nil, limit: nil)
        options = {
            domain: @domain
        }
        options[:query] = q if q
        options[:maxResults] = (limit || 500)
        users = @admin.list_users(options)
        users.users
    end

    def get_user(user_id:)
        options = {
            domain: @domain
        }
        options[:query] = user_id
        options[:maxResults] = 1
        users = @admin.list_users(options)
        users.users[0]
    end


    def get_available_rooms(room_ids:, start_param:, end_param:)
        now = Time.now
        start_param = ensure_ruby_date((start_param || now))
        end_param = ensure_ruby_date((end_param || (now + 1.hour)))

        freebusy_items = []
        room_ids.each do |room|
            freebusy_items << Google::Apis::CalendarV3::FreeBusyRequestItem.new(id: room)
        end

        options = {
            items: freebusy_items,
            time_min: start_param,
            time_max: end_param
        }
        freebusy_request = Google::Apis::CalendarV3::FreeBusyRequest.new options

        events = @calendar.query_freebusy(freebusy_request).calendars
        events.delete_if {|email, resp| !resp.busy.empty?  }
    end

    def delete_booking(room_id:, booking_id:)
        @calendar.delete_event(room_id, booking_id)
    end

    def get_bookings(email, start_param, end_param)
        if start_param.nil?
            start_param = DateTime.now
            end_param = DateTime.now + 1.hour
        end

        events = calendar.list_events(email, time_min: start_param, time_max: end_param).items
    end

    def create_booking(room_email:, start_param:, end_param:, subject:, description:nil, current_user:, attendees: nil, recurrence: nil, timezone:'Sydney')
        description = String(description)
        attendees = Array(attendees)

        # Get our room
        room = Orchestrator::ControlSystem.find_by_email(room_email)

        # Ensure our start and end params are Ruby dates and format them in Graph format
        start_param = ensure_ruby_date(start_param)
        end_param = ensure_ruby_date(end_param)

        event_params = {
            start: Google::Apis::CalendarV3::EventDateTime.new (date_time: start_param, timezone: timezone),
            end: Google::Apis::CalendarV3::EventDateTime.new (date_time: end_param, timezone: timezone),
            summary: subject,
            description: description
        }
    
        # Add the room as an attendee
        room_attendee_options = {
            resource: true,
            display_name: room.name,
            email: room_email,
            response_status: 'accepted'
        }
        attendees = [
            Google::Apis::CalendarV3::EventAttendee.new room_attendee_options
        ]

        # Add the attendees
        attendees.map!{|a|
            attendee_options = {
                display_name: a[:name],
                email: a[:email]
            }
            Google::Apis::CalendarV3::EventAttendee.new attendee_options
        }
        event_params[:attendees] = attendees

        # Add the current_user as an attendee
        event_params[:creator] = Google::Apis::CalendarV3::Event::Creator.new { display_name: current_user.name, email: current_user.email }

        event = Google::Apis::CalendarV3::Event.new event_params

        @calendar.insert_event(room_email, event)
    end


    # Takes a date of any kind (epoch, string, time object) and returns a time object
    def ensure_ruby_date(date) 
        if !(date.class == DateTime)
            if string_is_digits(date)

                # Convert to an integer
                date = date.to_i

                # If JavaScript epoch remove milliseconds
                if date.to_s.length == 13
                    date /= 1000
                end

                # Convert to datetimes
                date = DateTime.at(date)           
            else
                date = DateTime.parse(date)                
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
