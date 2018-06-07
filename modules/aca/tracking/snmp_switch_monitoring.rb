# frozen_string_literal: true
# encoding: ASCII-8BIT

module Aca; end
module Aca::Tracking; end

class Aca::Tracking::SnmpSwitchMonitoring
    include ::Orchestrator::Constants

    descriptive_name 'ACA SNMP Switch Monitoring'
    generic_name :SNMP_Trap
    implements :logic

    V1_Trap = 4
    Inform = 6
    V2_Trap = 7

    def on_load
        @boots = Time.now.to_i
        on_update
    end

    def on_update
        # Ensure server is stopped
        on_unload
        configure_server
    end

    def on_unload
        if @server
            @server.close
            @server = nil

            # Stop the server if started
            logger.info "server stopped"
        end
    end

    # Returns the time in seconds since the Agent booted
    #
    # @return [Integer] the time in seconds since boot
    def v3_time
        Time.now.to_i - @boots
    end

    protected

    def configure_server
        port = setting(:port) || 162

        @server = thread.udp { |data, ip, port|
            process(data, ip, port)
        }.bind('0.0.0.0', port).start_read

        logger.info "trap server started"
    end

    def new_message(data, ip, port)
        # Grab the message version
        asn_tree = ::OpenSSL::ASN1.decode(data)
        headers = asn_tree.value
        version = headers[0].value

        # Extract the community / engine id to look up the appropriate handler
        if version == 3
            sec_params_asn = ::OpenSSL::ASN1.decode(headers[2].value).value
            community = sec_params_asn[0].value # technically the engine_id
        elsif [1, 2].include?(version)
            community = headers[1].value
        else
            logger.warn "unknown SNMP version #{version}"
            return
        end

        # Extract the PDU payload
        if version == 3
            security = setting(community)
            if security
                request_pdu, engine_id, engine_boots, engine_time = ::NETSNMP::Message.decode(data, security_parameters: security)
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

            @server.send(ip, port, encoded_response)
            inform(request_pdu, ip, port)

        when V1_Trap, V2_Trap
            logger.debug { "received trap from #{ip}" }
            # reference: https://github.com/hallidave/ruby-snmp/blob/320e2395c082c8f54f070ce3be05d96f1dbfb500/lib/snmp/pdu.rb#L354
            inform(request_pdu, ip, port)
        else
            logger.debug { "ignoring unexpected SNMP request type #{request_pdu.type}" }
        end
    rescue => e
        logger.print_error e, 'processing SNMP message'
    end

    # Send response to the appropriate switch
    def inform(pdu, ip, port)
        # TODO:: map the switches to IP's so we can route signals
        logger.debug { "informing switch #{ip} of trap #{pdu.oid} and #{pdu.value}" }
    end
end
