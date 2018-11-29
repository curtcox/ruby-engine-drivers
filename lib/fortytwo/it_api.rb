require 'active_support/time'
require 'uv-rays'
require 'json'

module Fortytwo; end;

class Fortytwo::ItApi
    def initialize(
            client_id:,
            client_secret:,
            auth_domain:,
            api_domain:
        )
        @api_domain = api_domain
        oauth_options = {
            site: auth_domain,
            token_url: "#{auth_domain}token"
        }
        @api_client ||= OAuth2::Client.new(
            client_id,
            client_secret,
            oauth_options
        )
    end

    def api_request(request_method:, endpoint:, data:nil, query:{}, headers:nil)
        headers = Hash(headers)
        query = Hash(query)
        # Convert our request method to a symbol and our data to a JSON string
        request_method = request_method.to_sym
        data = data.to_json if !data.nil? && data.class != String

        headers['Authorization'] = "Bearer #{api_token}"

        api_path = "#{@api_domain}#{endpoint}"

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

    def get_users(q: nil, limit: 100, org_ids:nil, emails:nil)
        # If we have a query and the query has at least one space
        if q && q.include?(" ")
            # Split it into word tokens
            queries = q.split(" ")
            filter_params = []
            # For each word, create a filtering statement
            queries.each do |q|
                filter_params.push("(startswith(firstName,'#{q}') or startswith(lastName,'#{q}') or startswith(email,'#{q}'))")
            end
            # Join these filtering statements using 'or' and add accountEnabled filter
            filter_param = filter_params.join(" and ")
        elsif q && !q.include?(" ")
            filter_param = "startswith(firstName,'#{q}') or startswith(lastName,'#{q}') or startswith(email,'#{q}')"
        elsif org_ids
            filter_param = "organisation/externalId in ('#{org_ids.join('\',\'')}')"
        elsif emails
            filter_param = "email in ('#{emails.join('\',\'')}')"
        end
        query_params = {
            '$top': limit,
            '$expand': 'organisation'
        }
        query_params['$filter'] = filter_param if defined? filter_param
        query_params.compact!
        response = api_request(request_method: 'get', endpoint: 'user', query: query_params)
        JSON.parse(response.body)['value']
    end

    def get_orgs(q: nil, limit: 100, ids:nil)
        # If we have a query and the query has at least one space
        if q && q.include?(" ")
            # Split it into word tokens
            queries = q.split(" ")
            filter_params = []
            # For each word, create a filtering statement
            queries.each do |q|
                filter_params.push("(startswith(name,'#{q}') or startswith(description,'#{q}') or startswith(url,'#{q}'))")
            end
            # Join these filtering statements using 'or' and add accountEnabled filter
            filter_param = filter_params.join(" and ")
        elsif q && !q.include?(" ")
            filter_param = "startswith(name,'#{q}') or startswith(description,'#{q}') or startswith(url,'#{q}')"
        elsif ids
            filter_param = "externalId in ('#{ids.join('\',\'')}')"
        end
        query_params = {
            '$top': limit
        }
        query_params['$filter'] = filter_param if defined? filter_param
        query_params.compact!
        response = api_request(request_method: 'get', endpoint: 'org', query: query_params)
        JSON.parse(response.body)['value']
    end


    protected

    def api_token
        # For now just get a new token each time. In the future we will store the token and check if it expires
        @api_client.client_credentials.get_token.token
    end
end
