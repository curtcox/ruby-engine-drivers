# frozen_string_literal: true
# encoding: ASCII-8BIT

require 'singleton'

module Cisco; end
class Cisco::CatalystOffloader
    include Singleton

    class Proxy
        def initialize(reactor, snmp_settings)
            @reactor = reactor
            @snmp_settings = snmp_settings
            @defer = nil

            @terminated = false
            @connected = false

            connect
        end

        ParserSettings = {
            callback: lambda do |byte_str|
                return false if byte_str.bytesize < 4
                length = byte_str[0...4].unpack('V')[0] + 4
                return length if byte_str.length >= length
                false
            end
        }.freeze

        def connect(defer = @reactor.defer)
            @connecting = defer.promise
            @tokeniser = ::UV::AbstractTokenizer.new(ParserSettings)

            # Process response data
            @connection = @reactor.tcp { |data, socket|
                @tokeniser.extract(data).each do |response|
                    next unless @defer
                    begin
                        @defer.resolve Marshal.load(response)
                    rescue => e
                        @defer.reject e
                    end
                end
            }

            # Attempt to connect to offload process
            @connection.connect('127.0.0.1', 30001) { |socket|
                @connected = true
                defer.resolve(true)
                socket.start_read

                write(:client, @snmp_settings)
            }.finally {
                @defer&.reject RuntimeError.new('connection lost')
                @defer = nil

                if @connected
                    @connected = false
                    defer = @reactor.defer
                elsif @terminated
                    defer.reject RuntimeError.new('failed to connect')
                end

                connect(defer) unless @terminated
            }
        end

        def write(*args)
            raise "connection not ready" unless @connected
            msg =  Marshal.dump(args)
            @connection.write("#{[msg.length].pack('V')}#{msg}")
        end

        def disconnect
            @terminated = true
            @connection.close
        end

        # Proxied methods:
        def processing
            @defer
        end

        def promise
            @defer.promise
        end

        def new_setting(snmp_settings)
            @snmp_settings = snmp_settings
            @connecting.then { write(:client, snmp_settings) }
            @defer&.reject RuntimeError.new('client closed by user')
            @defer = nil
        end

        def new_client
            @connecting.then { write(:new_client) }
            @defer&.reject RuntimeError.new('client closed by user')
            @defer = nil
        end

        def close
            @connecting.then { write(:close) }
            @defer&.reject RuntimeError.new('client closed by user')
            @defer = nil
        end

        def query_index_mappings
            raise "processing in progress" if @defer
            @connecting.then { write(:query_index_mappings) }
            @defer = @reactor.defer
            @defer.promise.value
        end

        def query_interface_status
            raise "processing in progress" if @defer
            @connecting.then { write(:query_interface_status) }
            @defer = @reactor.defer
            @defer.promise.value
        end

        def query_snooping_bindings
            raise "processing in progress" if @defer
            @connecting.then { write(:query_snooping_bindings) }
            @defer = @reactor.defer
            @defer.promise.value
        end
    end

    def initialize
        Libuv::Reactor.default.schedule { start_process } if !defined?(::Rake::Task)
    end

    def register(reactor, snmp_settings)
        Proxy.new(reactor, snmp_settings)
    end

    def start_process
        # Start the rake task that will do the SNMP processing
        @process = @reactor.spawn('rake', args: "offload:catalyst_snmp['30001']")
        @process.finally do
            STDOUT.puts "offload task closed! Restarting in 5s..."
            @reactor.scheduler.in('5s') do
                @process = @reactor.spawn('rake', args: "offload:catalyst_snmp['30001']")
            end
        end
    end
end
