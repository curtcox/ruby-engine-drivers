require 'active_support/time'
require 'microsoft/officenew'
require 'microsoft/office/model'
require 'microsoft/office/user'
require 'microsoft/office/contact'
require 'microsoft/office/event'
module Microsoft
    class Error < StandardError
        class ResourceNotFound < Error; end
        class InvalidAuthenticationToken < Error; end
        class BadRequest < Error; end
        class ErrorInvalidIdMalformed < Error; end
        class ErrorAccessDenied < Error; end
    end
end

class Microsoft::Officenew; end

##
# This class provides a client to interface between Microsoft Graph API and ACA Engine. Instances of this class are
# primarily only used for:
#   -
class Microsoft::Officenew::Client

    ##
    # Initialize the client for making requests to the Office365 API.
    # @param [String] client_id The client ID of the application registered in the application portal or Azure
    # @param [String] client_secret The client secret of the application registered in the application portal or Azure
    # @param [String] app_site The site in which to send auth requests. This is usually "https://login.microsoftonline.com"
    # @param [String] app_token_url The token URL in which to send token requests
    # @param [String] app_scope The oauth scope to pass to token requests. This is usually "https://graph.microsoft.com/.default"
    # @param [String] graph_domain The domain to pass requests to Graph API. This is usually "https://graph.microsoft.com"
    def initialize(
            client_id:,
            client_secret:,
            app_site:,
            app_token_url:,
            app_scope:,
            graph_domain:
        )
        @client_id = client_id
        @client_secret = client_secret
        @app_site = app_site
        @app_token_url = app_token_url
        @app_scope = app_scope
        @graph_domain = graph_domain
        oauth_options = { site: @app_site,  token_url: @app_token_url }
        oauth_options[:connection_opts] = { proxy: @internet_proxy } if @internet_proxy
        @graph_client ||= OAuth2::Client.new(
            @client_id,
            @client_secret,
            oauth_options
        )
    end

    ##
    # Retrieve a list of users stored in Office365
    # 
    # @param q [String] The query param which filters all users without a name or email matching this string
    # @param limit [String] The maximum number of users to return
    def get_users(q: nil, limit: nil)

        # If we have a query and the query has at least one space
        if q && q.include?(" ")
            # Split it into word tokens
            queries = q.split(" ")
            filter_params = []

            # For each word, create a filtering statement
            queries.each do |q|
                filter_params.push("(startswith(displayName,'#{q}') or startswith(givenName,'#{q}') or startswith(surname,'#{q}') or startswith(mail,'#{q}'))")
            end

            # Join these filtering statements using 'or' and add accountEnabled filter
            filter_param = "(accountEnabled eq true) and #{filter_params.join(" and ")}"
        else
            # Or just add the space-less query to be checked for each field
            filter_param = "(accountEnabled eq true) and (startswith(displayName,'#{q}') or startswith(givenName,'#{q}') or startswith(surname,'#{q}') or startswith(mail,'#{q}'))" if q
        end

        # If we have no query then still only grab enabled accounts
        filter_param = "accountEnabled eq true" if q.nil?

        # Put our params together and make the request
        query_params = {
            '$filter': filter_param,
            '$top': limit
        }.compact
        endpoint = "/v1.0/users"
        request = graph_request(request_method: 'get', endpoints: [endpoint], query: query_params)
        check_response(request)

        # Return the parsed user data
        JSON.parse(request.body)['value'].map {|u| Microsoft::Officenew::User.new(client: self, user: u)}
    end

    ##
    # Retrieve a list of contacts for some passed in mailbox
    # 
    # @param mailbox [String] The mailbox email of which we want to grab the contacts for
    # @param q [String] The query param which filters all contacts without a name or email matching this string
    # @param limit [String] The maximum number of contacts to return
    def get_contacts(mailbox:, q:nil, limit:nil)
        query_params = { '$top': (limit || 1000) }
        query_params['$filter'] = "startswith(displayName, '#{q}') or startswith(givenName, '#{q}') or startswith(surname, '#{q}') or emailAddresses/any(a:a/address eq  '#{q}')" if q
        endpoint = "/v1.0/users/#{mailbox}/contacts"
        request = graph_request(request_method: 'get', endpoints: [endpoint], query: query_params)
        check_response(request)
        JSON.parse(request.body)['value'].map {|c| Microsoft::Officenew::Contact.new(client: self, contact: c)}
    end


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
    

    protected

    ##
    # Passes back either a stored bearer token for Graph API that has yet to expire or
    # grabs a new token and stores it along with the expiry date.
    def graph_token
        # Check if we have a token in couchbase
        token = User.bucket.get("office-token", quiet: true)

        # If we don't have a token
        if token.nil? || token[:expiry] <= Time.now.to_i
            # Get a new token with the passed in scope
            new_token = @graph_client.client_credentials.get_token({
                :scope => @app_scope
            })
            # Save both the token and the expiry details
            new_token_model = {
                token: new_token.token,
                expiry: Time.now.to_i + new_token.expires_in,
            }
            User.bucket.set("office-token", new_token_model)
            return new_token.token
        else
            # Otherwise, use the existing token
            token[:token]
        end
    end

    ##
    # The helper method that abstracts calls to graph API. This method allows for both single requests and 
    # bulk requests using the $batch endpoint.
    def graph_request(request_method:, endpoints:, data:nil, query:{}, headers:{}, bulk: false)
        if bulk
            uv_request_method = :post
            graph_path = "#{@graph_domain}/v1.0/$batch"
            query_string = "?#{query.map { |k,v| "#{k}=#{v}" }.join('&')}"
            data = {
                requests: endpoints.each_with_index.map { |endpoint, i| { id: i, method: request_method.upcase, url: "#{endpoint}#{query_string}" } }
            }
            query = {}
        else
            uv_request_method = request_method.to_sym
            graph_path = "#{@graph_domain}#{endpoints[0]}"
        end

        headers['Authorization'] = "Bearer #{graph_token}"
        headers['Content-Type'] = ENV['GRAPH_CONTENT_TYPE'] || "application/json"
        headers['Prefer'] = ENV['GRAPH_PREFER'] || 'outlook.timezone="Australia/Sydney"'

        log_graph_request(request_method, data, query, headers, graph_path, endpoints)

        graph_api = UV::HttpEndpoint.new(@graph_domain, { inactivity_timeout: 25000, keepalive: false })
        response = graph_api.__send__(uv_request_method, path: graph_path, headers: headers, body: data.to_json, query: query)

        response.value
    end

    def graph_date(date)
        Time.at(date).utc.iso8601.split("+")[0]
    end

    def log_graph_request(request_method, data, query, headers, graph_path, endpoints=nil)
        STDERR.puts "--------------NEW GRAPH REQUEST------------"
        STDERR.puts "#{request_method} to #{graph_path}"
        STDERR.puts "Data:"
        STDERR.puts data if data
        STDERR.puts "Query:"
        STDERR.puts query if query
        STDERR.puts "Headers:"
        STDERR.puts headers if headers
        STDERR.puts "Endpoints:"
        STDERR.puts endpoints if endpoints
        STDERR.puts '--------------------------------------------'
        STDERR.flush
    end

    def check_response(response)
        puts "CHECKING RESPONSE"
        puts response.body if response.body
        case response.status
        when 200, 201, 204
            return
        when 400
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

end