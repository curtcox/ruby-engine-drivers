# frozen_string_literal: true
# encoding: ASCII-8BIT

require 'set'
require 'ipaddr'
require 'protocols/snmp'
require 'aca/trap_dispatcher'

module Cisco; end
module Cisco::Switch; end

::Orchestrator::DependencyManager.load('Aca::Tracking::SwitchPort', :model, :force)
::Aca::Tracking::SwitchPort.ensure_design_document!

class Cisco::Switch::MerakiSNMP
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security

    descriptive_name 'Cisco Meraki SNMP'
    generic_name :Snooping
    udp_port 161

    default_settings({
        building: 'building_code',
        reserve_time: 5.minutes.to_i,
        snmp_options: {
            version: "v2c",
            community: 'public',
            timeout: 4
        }
    })

    def on_load
        # flag to indicate if processing is occuring
        @if_mappings = {}

        # Interfaces that we know are connected to the network
        @connected_interfaces = ::Set.new
        self[:interfaces] = [] # This will be updated via query

        begin
            on_update

            # Load the current state of the switch from the database
            query = ::Aca::Tracking::SwitchPort.find_by_switch_ip(@remote_address)
            query.each do |detail|
                details = detail.details
                interface = detail.interface
                self[interface] = details

                if details.connected
                    @connected_interfaces << interface
                end
            end
        rescue => error
            logger.print_error error, 'loading persisted details'
        end

        self[:interfaces] = @connected_interfaces.to_a
        self[:reserved] = []
    end

    def on_update
        new_client if @resolved_ip
        @remote_address = remote_address.downcase

        self[:name] = @switch_name = setting(:switch_name)
        self[:ip_address] = @remote_address
        self[:building] = setting(:building)
        self[:level] = setting(:level)
    end

    def on_unload
        if @processing
            client = @client
            @processing.finally { client.close }
        else
            @client&.close
        end
        @client = nil

        td = ::Aca::TrapDispatcher.instance
        td.ignore(@resolved_ip) if @resolved_ip
    end

    def is_processing?
        "IP resolved to #{@resolved_ip}\ntransport online #{!!@client}\nprocessing #{!!@processing}"
    end

    def hostname_resolution(ip)
        td = ::Aca::TrapDispatcher.instance
        td.ignore(@resolved_ip) if @resolved_ip
        @resolved_ip = ip

        logger.debug { "Registering for trap notifications from #{ip}" }
        td.register(thread, logger, ip) { |pdu| check_link_state(pdu) }

        new_client
    end

    def check_link_state(pdu)
        logger.warn "community mismatch: trap #{pdu.community.inspect} != #{@community.inspect}" unless @community == pdu.community

        # Looks like: http://www.alvestrand.no/objectid/1.3.6.1.2.1.2.2.1.html
        # <NETSNMP::PDU:0x007ffed43bb1b0 @version=0, @community="public",
        #   @error_status=0, @error_index=3, @type=4, @varbinds=[
        #       #<NETSNMP::Varbind:0x007ffed43bb048 @oid="1.3.6.1.2.1.2.2.1.1.26", @type=nil, @value=26>, (ifEntry)
        #       #<NETSNMP::Varbind:0x007ffed43bae68 @oid="1.3.6.1.2.1.2.2.1.2.26", @type=nil, @value="GigabitEthernet1/0/19">,
        #       #<NETSNMP::Varbind:0x007ffed43bacb0 @oid="1.3.6.1.2.1.2.2.1.3.26", @type=nil, @value=6>,  (port type 6 == ethernet)
        #       #<NETSNMP::Varbind:0x007ffed43baad0 @oid="1.3.6.1.4.1.9.2.2.1.1.20.26", @type=nil, @value="up">
        #   ], @request_id=1>

        ifIndex = nil
        state = nil
        pdu.varbinds.each do |var|
            oid = var.oid
            # 1.3.6.1.2.1.2.2.1 == ifEntry
            if oid.start_with?('1.3.6.1.2.1.2.2.1.1')
                # port description
                ifIndex = var.value
            elsif oid.start_with?('1.3.6.1.4.1.9.2.2.1.1.20')
                # port state
                state = var.value.to_sym
            end
        end

        if ifIndex && state
            if @processing
                @processing.finally { on_trap(ifIndex, state) }
            else
                on_trap(ifIndex, state)
            end
        end
    end

    # The SNMP trap handler will notify of changes in interface state
    def on_trap(ifIndex, state)
        interface = @if_mappings[ifIndex]
        if interface.nil?
            logger.debug { "Notify: no interface found for #{ifIndex} - #{state}" }
            return
        end

        case state
        when :up
            logger.debug { "Notify Up: #{interface}" }
            @connected_interfaces << interface
        when :down
            logger.debug { "Notify Down: #{interface}" }
            # We are no longer interested in this interface
            @connected_interfaces.delete(interface)
            remove_lookup(interface)
        end

        self[:interfaces] = @connected_interfaces.to_a
    end

    # Index short name lookup
    # ifName: 1.3.6.1.2.1.31.1.1.1.1.xx  (where xx is the ifIndex)
    def query_index_mappings
        return :not_ready unless @client
        return :currently_processing if @processing

        logger.debug '==> mapping ifIndex to port names <=='
        @scheduled_if_query = false

        client = @client
        mappings = {}
        @processing = task do
            client.walk(oid: '1.3.6.1.2.1.31.1.1.1.1').each do |oid_code, value|
                oid_code = oid_code[23..-1]
                mappings[oid_code.to_i] = value.downcase.gsub(' ', '')
            end
        end
        @processing.finally {
            @processing = nil
            client.close if client != @client
        }
        @processing.then {
            logger.debug { "<== found #{mappings.length} ports ==>" }
            if mappings.empty?
                @scheduled_if_query = true
            else
                @if_mappings = mappings
            end
        }.value
    end

    # ifOperStatus: 1.3.6.1.2.1.2.2.1.8.xx == up(1), down(2), testing(3)
    def query_interface_status
        return :not_ready unless @client
        return :currently_processing if @processing

        logger.debug '==> querying interface status <=='

        client = @client
        if_mappings = @if_mappings
        remove_interfaces = []
        @processing = task do
            client.walk(oid: '1.3.6.1.2.1.2.2.1.8').each do |oid_code, value|
                oid_code = oid_code[20..-1]
                interface = if_mappings[oid_code.to_i]

                next unless interface

                case value
                when 1 # up
                    next if @connected_interfaces.include?(interface)
                    logger.debug { "Interface Up: #{interface}" }
                    if !@connected_interfaces.include?(interface)
                        @connected_interfaces << interface
                    end
                when 2 # down
                    next unless @connected_interfaces.include?(interface)
                    logger.debug { "Interface Down: #{interface}" }
                    # We are no longer interested in this interface
                    @connected_interfaces.delete(interface)
                else
                    next
                end
            end
        end
        @processing.finally {
            client.close if client != @client
            @processing = nil
        }
        @processing.then {
            logger.debug '<== finished querying interfaces ==>'
            remove_interfaces.each { |iface| remove_lookup(interface) }
            self[:interfaces] = @connected_interfaces.to_a
        }.value
    end

    def query_connected_devices
        if @processing
            logger.debug 'Skipping device query... busy processing'
            return
        end
        logger.debug 'Querying for connected devices'
        query_index_mappings if @if_mappings.empty? || @scheduled_if_query
        query_interface_status
    ensure
        rebuild_client
    end


    protected


    def new_client
        schedule.clear

        @snmp_settings = setting(:snmp_options).to_h.symbolize_keys
        @snmp_settings[:host] = @resolved_ip
        @community = @snmp_settings[:community]
        rebuild_client

        # Grab the initial state
        next_tick do
            query_connected_devices
        end

        # Connected device polling (in case a trap was dropped by the network)
        # Also expires any desk reservations every 1min
        schedule.every(57000 + rand(5000)) do
            query_connected_devices
        end

        # There is a possibility that these will change on switch reboot
        schedule.every('15m') { @scheduled_if_query = true }
    end

    def rebuild_client
        @client.close if @client && @processing.nil?
        @client = NETSNMP::Client.new(@snmp_settings)
    end

    def received(data, resolve, command)
        logger.error "unexpected response:\n#{data.inspect}"
        :abort
    end

    def remove_lookup(interface)
        # Update the status of the switch port
        model = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{@remote_address}-#{interface}")
        if model
            model.disconnected
            details = model.details
            self[interface] = details
        else
            self[interface] = nil
        end
    end
end
