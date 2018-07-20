# encoding: UTF-8
# frozen_string_literal: true

require 'netsnmp'

module Protocols; end

# A simple proxy object for netsnmp
# See https://github.com/swisscom/ruby-netsnmp
class Protocols::Snmp
    def initialize(logger, scheduler, timeout = 2000)
        @logger = logger
        @timeout = timeout
        @scheduler = scheduler
        @client = Aca::SNMPClient.instance
        @request_queue = []
    end

    def register(thread, ip, port)
        close

        @ip = ip
        @port = port
        @thread = thread

        @client.register(thread, ip) do |data, ip, port|
            defer = @request_queue.shift
            defer.resolve(data) if defer
        end
    end

    def close
        @client.ignore(@ip) if @ip
    end

    def send(payload)
        # Send the request
        if @request_queue.empty?
            @client.send(@ip, @port, payload)
        else
            @request_queue[-1].promise.finally do
                @client.send(@ip, @port, payload)
            end
        end

        # Track response
        defer = @thread.defer
        @request_queue << defer

        # Create timeout
        timeout = @scheduler.in(@timeout) { defer.reject(::Timeout::Error.new("Timeout after #{@timeout}")) }
        promise = defer.promise

        # Cancel timeout
        promise.finally { |data| timeout.cancel }

        # Wait for IO response
        promise.value
    end
end
