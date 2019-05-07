# encoding: UTF-8
# frozen_string_literal: true

require 'netsnmp'
require 'aca/trap_dispatcher'

module Protocols; end

# A simple proxy object for netsnmp
# See https://github.com/swisscom/ruby-netsnmp
class Protocols::Snmp
    def initialize(mod, timeout = 2000)
        @logger = mod.logger
        @thread = mod.thread
        @timeout = timeout

        # Less overhead with the thread scheduler
        @scheduler = @thread.scheduler
    end

    attr_reader :request

    def start_server
        @server = @thread.udp { |data, ip, port|
            if ip == @ip
                if @request
                    @request.resolve(data)
                    @request = nil
                else
                    @logger.debug 'SNMP received data with no request waiting'
                end
            end
        }.bind('0.0.0.0', 0).start_read
    end

    def register(ip, port)
        start_server unless @server
        @ip = ip
        @port = port
    end

    def close
        @server.close
        @server = nil
        @ip = nil
        @port = nil
        if @request
            @request.reject StandardError.new('connection closed')
            @request = nil
        end
    end

    def send(payload)
        # Send the request
        raise 'SNMP request already waiting resonse. Overlapping IO not permitted' if @request

        # Track response
        @request = @thread.defer
        @server.send(@ip, @port, payload)

        # Create timeout
        timeout = @scheduler.in(@timeout) do
            @request.reject(::Timeout::Error.new("Timeout after #{@timeout}"))
            @logger.debug 'SNMP timeout occurred'
            @request = nil
        end
        promise = @request.promise
        promise.finally { timeout.cancel }

        # Wait for IO response
        promise.value
    end
end
