# encoding: UTF-8
# frozen_string_literal: true

require 'libuv'
require 'netsnmp'
require 'singleton'

module Aca; end

class Aca::SnmpManager
    def initialize
        # IP => callback
        @mappings = {}

        # Server start time
        @boots = Time.now.to_i
    end

    V1_Trap = 4
    Inform = 6
    V2_Trap = 7

    # provide a callback for responding to informs
    def send_cb(&block)
        @send_cb = block
    end

    def register(thread, logger, ip, **settings, &block)
        @mappings[ip] = [thread, logger, settings, block]
    end

    def ignore(ip)
        @mappings.delete ip
    end

    # Returns the time in seconds since the Agent booted
    #
    # @return [Integer] the time in seconds since boot
    def v3_time
        Time.now.to_i - @boots
    end

    # Process a message from an agent
    def new_message(data, ip, port)
        thread, logger, settings, callback = @mappings[ip]
        return unless thread

        # Grab the message version
        asn_tree = ::OpenSSL::ASN1.decode(data)
        headers = asn_tree.value
        version = headers[0].value

        # Extract the community / engine id to look up the appropriate handler
        if version == 3
            sec_params_asn = ::OpenSSL::ASN1.decode(headers[2].value).value
            community = sec_params_asn[0].value # technically the engine_id
        elsif [0, 1, 2].include?(version)
            # version == 0 : SNMP v1
            community = headers[1].value
        else
            logger.warn "unknown SNMP version #{version}"
            return
        end

        # Extract the PDU payload
        if version == 3
            security = settings[community]
            if security
                request_pdu, _engine_id, _engine_boots, _engine_time = ::NETSNMP::Message.decode(data, security_parameters: security)
            else
                logger.warn "no security defined for SNMPv3 messages to #{community.inspect}"
                return
            end
        else
            request_pdu = ::NETSNMP::PDU.decode(data)
        end

        # Process the request
        case request_pdu.type
        when Inform
            logger.debug { "received inform from #{ip}" }

            # Acknowledge the inform
            if request_pdu.version == 3
                engine_id = community
                context = ""
                pdu = ::NETSNMP::ScopedPDU.build(:response,
                    headers: [community, context],
                    varbinds: request_pdu.varbinds.collect{|v| {oid: v.oid} },
                    request_id: request_pdu.request_id
                )
                encoded_response = ::NETSNMP::Message.encode(pdu, security_parameters: security, engine_boots: @boots, engine_time: v3_time)
            else
                response_pdu = ::NETSNMP::PDU.build(:response,
                    headers: [request_pdu.version, request_pdu.community],
                    varbinds: request_pdu.varbinds.collect{|v| {oid: v.oid} },
                    request_id: request_pdu.request_id
                )
                encoded_response = response_pdu.to_der
            end

            @send_cb.call(ip, port, encoded_response)
            thread.schedule { callback.call(request_pdu, ip, port) }

        when V1_Trap, V2_Trap
            logger.debug { "received trap from #{ip}" }
            # reference: https://github.com/hallidave/ruby-snmp/blob/320e2395c082c8f54f070ce3be05d96f1dbfb500/lib/snmp/pdu.rb#L354
            thread.schedule { callback.call(request_pdu, ip, port) }
        else
            logger.debug { "ignoring unexpected SNMP request type #{request_pdu.type}" }
        end
    rescue => e
        logger.print_error e, 'processing SNMP message'
    end
end

class Aca::TrapDispatcher
    include Singleton

    def initialize
        # Configure our manager
        @manager = ::Aca::SnmpManager.new

        # Bind to the UDP port (162)
        @reactor = Libuv::Reactor.default
        @reactor.schedule { configure_server }
    end

    def register(thread, logger, ip, **settings, &block)
        @reactor.schedule { @manager.register(thread, logger, ip, **settings, &block) }
        nil
    end

    def ignore(ip)
        @reactor.schedule { @manager.ignore(ip) }
        nil
    end

    protected

    def configure_server
        @server = @reactor.udp { |data, ip, port|
            @manager.new_message(data, ip, port)
        }.bind('0.0.0.0', 162).start_read

        @manager.send_cb do |ip, port, response|
            @server.send(ip, port, response)
        end
    end
end

class Aca::SNMPClient
    include Singleton

    def initialize
        @mappings = {}

        # Bind to the UDP port (161)
        @reactor = Libuv::Reactor.default
        @reactor.schedule { configure_server }
    end

    def register(thread, ip, &callback)
        @reactor.schedule { @mappings[ip] = [thread, callback] }
        nil
    end

    def ignore(ip)
        @reactor.schedule { @mappings.delete(ip) }
        nil
    end

    def send(ip, port, data)
        @reactor.schedule { @server.send(ip, port, data) }
        nil
    end

    protected

    def configure_server
        @server = @reactor.udp { |data, ip, port|
            thread, callback = @mappings[ip]
            thread&.schedule { callback.call(data, ip, port) }
        }.bind('0.0.0.0', 161).start_read
    end
end
