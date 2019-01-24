require 'active_support/time'
require 'uv-rays'
require 'json'
require 'jwt'

# Key: r5xPDqu-SOa78h3cqgndFg
# Secret: cghDnHqVEeSSoPRy0oQXfBjsrmPWDqm81dNr
# Token: eyJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJrRUtqRVJvQlIzT0hacXQ4MGp0VVVnIn0.CJWvJmDrdIbJT7EXZtKMOhl-3Y_u-Mdzn5W34725t0U
# JWT (long expiry): eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJhdWQiOm51bGwsImlzcyI6InI1eFBEcXUtU09hNzhoM2NxZ25kRmciLCJleHAiOjE3NjcwMTMxNDAsImlhdCI6MTU0ODAyOTE1Nn0.P5VrccVn3GGardbqajeiILb7pGaMMThFUIlxK0Fcc_Y
module Zoom; end;

class Zoom::Meeting
    def initialize(
            key:,
            secret:
        )
        @key = key
        @secret = secret
        @api_domain = 'https://api.zoom.us'
        @api_path = '/v2/'
        @api_full_path = "#{@api_domain}#{@api_path}"
    end


    # {
    #   "topic": "Test Meeting",
    #   "agenda": "Test the Zoom API",
    #   "type": 2, => Scheduled Meeting
    #   "start_time": "2018-02-21T16:00:00",
    #   "duration": 30,
    #   "timezone": "Australia/Sydney",
    #   "settings": {
    #     "host_video": true,
    #     "participant_video": true,
    #     "join_before_host": true,
    #     "mute_upon_entry": true,
    #     "use_pmi": true,
    #     "approval_type": 0,
    #     "audio": "both",
    #     "auto_recording": "none",
    #     "enforce_login": false
    #   }
    # }
    def create_meeting(owner_email:, start_time:, duration:nil, topic:, agenda:nil, countries:, timezone:'Australia/Sydney')
        zoom_params = {
            "topic": topic,
            "type": 2,
            "start_time": Time.at(start_time).iso8601,
            "duration": (duration || 30),
            "timezone": timezone,
            "settings": {
              "host_video": true,
              "participant_video": true,
              "join_before_host": true,
              "mute_upon_entry": true,
              "use_pmi": true,
              "approval_type": 0,
              "audio": "both",
              "auto_recording": "none",
              "enforce_login": false
            }
        }
        zoom_params['agenda'] = agenda if agenda
        response = api_request(request_method: 'post', endpoint: "users/#{owner_email}/meetings", data: zoom_params)
        JSON.parse(reponse.body)
    end

    protected

    def generate_jwt
        payload = {
            iss: @key,
            exp: (Time.now + 259200).to_i
        }

        # IMPORTANT: set nil as password parameter
        token = JWT.encode payload, @secret, 'HS256'
    end

    def api_request(request_method:, endpoint:, data:nil, query:{}, headers:nil)
        headers = Hash(headers)
        query = Hash(query)
        # Convert our request method to a symbol and our data to a JSON string
        request_method = request_method.to_sym
        data = data.to_json if !data.nil? && data.class != String

        headers['Authorization'] = "Bearer #{generate_jwt}"
        headers['Content-Type'] = "application/json"

        api_path = "#{@api_full_path}#{endpoint}"

        log_api_request(request_method, data, query, headers, api_path)


        api_options = {inactivity_timeout: 25000, keepalive: false}

        api = UV::HttpEndpoint.new(@api_domain, api_options)
        response = api.__send__(request_method, path: api_path, headers: headers, body: data, query: query)

        start_timing = Time.now.to_i
        response_value = response.value
        end_timing = Time.now.to_i
        return response_value
    end

    def log_api_request(request_method, data, query, headers, graph_path)
        STDERR.puts "--------------NEW GRAPH REQUEST------------"
        STDERR.puts "#{request_method} to #{graph_path}"
        STDERR.puts "Data:"
        STDERR.puts data if data
        STDERR.puts "Query:"
        STDERR.puts query if query
        STDERR.puts "Headers:"
        STDERR.puts headers if headers
        STDERR.puts '--------------------------------------------'
        STDERR.flush
    end

end
