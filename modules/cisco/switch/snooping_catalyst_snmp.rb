# frozen_string_literal: true
# encoding: ASCII-8BIT

require 'set'
require 'protocols/snmp'

module Cisco; end
module Cisco::Switch; end

::Orchestrator::DependencyManager.load('Aca::Tracking::SwitchPort', :model, :force)
::Aca::Tracking::SwitchPort.ensure_design_document!

class Cisco::Switch::SnoopingCatalystSNMP
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security

    descriptive_name 'Cisco Catalyst SNMP IP Snooping'
    generic_name :Snooping
    udp_port 161

    default_settings({
        building: 'building_code',
        reserve_time: 5.minutes.to_i
    })

    def on_load
        @check_interface = ::Set.new
        @reserved_interface = ::Set.new
        self[:interfaces] = [] # This will be updated via query

        on_update

        # Load the current state of the switch from the database
        query = ::Aca::Tracking::SwitchPort.find_by_switch_ip(remote_address)
        query.each do |detail|
            details = detail.details
            interface = detail.interface
            self[interface] = details

            if details.connected
                @check_interface << interface
            elsif details.reserved
                @reserved_interface << interface
            end
        end

        self[:interfaces] = @check_interface.to_a
        self[:reserved] = @reserved_interface.to_a
    end

    def on_update
        # TODO:: Register for trap callback

        self[:name] = @switch_name = setting(:switch_name)
        self[:ip_address] = remote_address
        self[:building] = setting(:building)
        self[:level] = setting(:level)

        @reserve_time = setting(:reserve_time) || 0
        @snooping ||= []
    end

    def connected
        proxy = Protocols::Snmp.new(self)
        @client = NETSNMP::Client.new({
            proxy: proxy, version: "2c",
            community: "public"
        })

        query_index_mappings
        schedule.in(1000) { query_connected_devices }
        schedule.every('1m') do
            query_connected_devices
            check_reservations if @reserve_time > 0
        end

        schedule.every('30m') do
            query_index_mappings
        end
    end

    def disconnected
        schedule.clear
    end

    def query_snooping_bindings
        # http://www.circitor.fr/Mibs/Html/C/CISCO-DHCP-SNOOPING-MIB.php#CdsBindingsEntry
        # cdsBindingsTable: 1.3.6.1.4.1.9.9.380.1.4.1
        #
        # A row instance contains the Mac address, IP address type, IP address, VLAN number, interface number, leased time, and status of this instance.

        @client.walk(oid: "1.3.6.1.4.1.9.9.380.1.4.1.1") do |oid_code, value|
            oid_code = oid_code.split('.')[-1]
            interface = @if_mappings[oid_code]
            logger.debug { "snooping #{oid_code}, #{interface}: #{value}" }

            next unless interface

            # TODO:: extract value data
        end
    end

    def query_index_mappings
        mappings = {}

        # Index short name lookup
        # ifName: 1.3.6.1.2.1.31.1.1.1.1.xx  (where xx is the ifIndex)
        # manager.walk(oid: "1.3.6.1.2.1.31.1.1.1.1").to_a

        logger.debug "Querying for index mappings"
        @client.walk(oid: "1.3.6.1.2.1.31.1.1.1.1") do |oid_code, value|
            oid_code = oid_code.split('.')[-1]
            logger.debug { "index #{oid_code}: #{value}" }
            mappings[oid_code] = value
        end

        @if_mappings = mappings
    end

    def query_interface_status
        # ifOperStatus: 1.3.6.1.2.1.2.2.1.8.xx == up(1), down(2), testing(3)
        # manager.walk(oid: "1.3.6.1.2.1.2.2.1.8").to_a

        # Lookup the name of the interface in the mappings
        logger.debug "Querying interface status"
        @client.walk(oid: "1.3.6.1.2.1.2.2.1.8") do |oid_code, value|
            oid_code = oid_code.split('.')[-1]
            interface = @if_mappings[oid_code]
            logger.debug { "iface #{oid_code}, #{interface}: #{value}" }

            next unless interface

            case value
            when 1 # up
                logger.debug { "Interface Up: #{interface}" }
                remove_reserved(interface)
                @check_interface << interface
            when 2 # down
                logger.debug { "Interface Down: #{interface}" }
                remove_lookup(interface)
            else
                next
            end
        end

        self[:interfaces] = @check_interface.to_a
    end

    def query_connected_devices
        logger.debug "Querying for connected devices"
        query_interface_status
        query_snooping_bindings
    end

    def update_reservations
        check_reservations
    end


    protected


    def received(data, resolve, command)
        logger.debug { "Switch sent #{data}" }
        data
    end

    def remove_lookup(interface)
        # We are no longer interested in this interface
        @check_interface.delete(interface)

        # Update the status of the switch port
        model = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{remote_address}-#{interface}")
        if model
            notify = model.disconnected
            details = model.details
            self[interface] = details

            # notify user about reserving their desk
            if notify
                self[:disconnected] = details
                @reserved_interface << interface
            end
        else
            self[interface] = nil
        end
    end

    def remove_reserved(interface)
        return unless @reserved_interface.include? interface
        @reserved_interface.delete interface
        self[:reserved] = @reserved_interface.to_a
    end

    def format(mac)
        mac.gsub(/(0x|[^0-9A-Fa-f])*/, "").downcase
    end

    def check_reservations
        remove = []

        # Check if the interfaces are still reserved
        @reserved_interface.each do |interface|
            details = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{remote_address}-#{interface}")
            remove << interface unless details.reserved?
            self[interface] = details.details
        end

        # Remove them from the reserved list if not
        if remove.present?
            @reserved_interface -= remove
            self[:reserved] = @reserved_interface.to_a
        end
    end

    def normalise(interface)
        # Port-channel == po
        interface.downcase.gsub('tengigabitethernet', 'te').gsub('gigabitethernet', 'gi').gsub('fastethernet', 'fa')
    end
end
