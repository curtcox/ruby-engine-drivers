# domino = IBM::Domino.new({
#     username: nil,
#     password: nil,
#     auth_hash: 'T1RTIFRlc3QxIFByb2plY3QgU0c6UEBzc3cwcmQxMjM=',
#     domain: 'http://sg-mbxpwv001.cn.asia.ad.pwcinternal.com',
#     timezone: 'Singapore'
# })
# res = nil
# reactor.run {
#     res = domino.get_bookings('mail/generic/otstest1projectsg.nsf', (Time.now - 1.day).midnight, (Time.now - 1.day).midnight + 3.days)
# }
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
        @headers = {
            'Authorization' => "Basic #{auth_hash}",
            'Content-Type' => 'application/json'
        }
        @domino_api = UV::HttpEndpoint.new(@domain, {inactivity_timeout: 25000})
    end

    def to_ibm_date(time)
        time.strftime("%Y-%m-%dT%H:%M:%SZ")
    end


    def get_bookings(database, starting, ending, days=nil)

        # Set our unchanging path
        path = "#{@domain}/#{database}/api/calendar/events"

        # Sent count to max
        query = {
            count: 100
        }

        # If we have a range use it
        if starting
            query[:since] = to_ibm_date(starting)
            query[:before] = to_ibm_date(ending)
        end

        response = @domino_api.get(path: path, headers: @headers, body: nil, query: query).value
        domino_bookings = JSON.parse(response.body)['events']

        bookings = []

        domino_bookings.each{ |booking|
            # booking = domino_bookings.sample
            bookings.push(get_attendees(booking, database))
        }
        bookings
    end

    def get_attendees(booking, database)
        path = "#{@domain}/#{database}/api/calendar/events/#{booking['id']}"
        # puts "Attendee path is #{path}"
        booking_request = @domino_api.get(path: path, headers: @headers).value
        booking_response = JSON.parse(booking_request.body)['events'][0]
        if booking_response['attendees']
            attendees = booking_response['attendees'].dup 
            attendees.map!{ |b|
                {
                    name: b['displayName'],
                    email: b['email']
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
end

