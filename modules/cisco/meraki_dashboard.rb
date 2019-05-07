# frozen_string_literal: true
# encoding: ASCII-8BIT

module Cisco; end

require 'net/http'
require 'singleton'

class Cisco::MerakiDashboard
    include Singleton

    def initialize
        @queue = Queue.new
        Thread.new { process_requests! }
    end

    def new_request(api_key, request)
        thread = Libuv::Reactor.current
        defer = thread.defer
        @queue << [defer, api_key, request]
        defer.promise.value
    end

    protected

    def process_requests!
        loop do
            defer, api_key, request = @queue.pop
            begin
                defer.resolve fetch(api_key, request)
            rescue => e
                defer.reject e
            end

            # rate limit the requests to 5 per-second
            # I believe this includes redirects
            sleep 0.4
        end
    end

    def fetch(api_key, location, limit = 3)
        raise ArgumentError, 'too many HTTP redirects' if limit == 0

        uri = URI(location)
        request = Net::HTTP::Get.new(uri)
        request['X-Cisco-Meraki-API-Key'] = api_key
        request['Content-Type'] = 'application/json'
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.open_timeout = 2
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.use_ssl = true
        response = http.request(request)

        case response
        when Net::HTTPSuccess
            JSON.parse(response.body, symbolize_names: true)
        when Net::HTTPRedirection
            location = response['location']
            fetch(api_key, location, limit - 1)
        else
            raise "error performing Meraki Dashboard request: #{response.status}"
        end
    rescue Net::OpenTimeout => e
        limit = limit - 1
        if limit > 0
            sleep 0.1
            retry
        else
            raise e
        end
    end
end
