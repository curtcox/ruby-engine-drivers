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

class Cisco::Switch::SnoopingCatalystSNMP
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security

    descriptive_name 'Cisco Catalyst SNMP IP Snooping'
    generic_name :Snooping
    udp_port 161

    default_settings({
        building: 'building_code',
        reserve_time: 5.minutes.to_i,
        snmp_options: {
            version: 1,
            community: 'public'
        },
        # Snooping takes ages on large switches
        response_timeout: 7000
    })

    def on_load
        # flag to indicate if processing is occuring
        @if_mappings = {}
        @scheduled_status_query = true

        # Interfaces that indicate they have a device connected
        @check_interface = ::Set.new

        # Interfaces that we know are connected to the network
        @connected_interfaces = ::Set.new

        @reserved_interface = ::Set.new
        self[:interfaces] = [] # This will be updated via query

        on_update

        # Load the current state of the switch from the database
        query = ::Aca::Tracking::SwitchPort.find_by_switch_ip(@remote_address)
        query.each do |detail|
            details = detail.details
            interface = detail.interface
            self[interface] = details

            if details.connected
                @check_interface << interface
                @connected_interfaces << interface
            elsif details.reserved
                @reserved_interface << interface
            end
        end

        self[:interfaces] = @connected_interfaces.to_a
        self[:reserved] = @reserved_interface.to_a
    end

    def on_update
        new_client if @resolved_ip
        @remote_address = remote_address.downcase

        self[:name] = @switch_name = setting(:switch_name)
        self[:ip_address] = @remote_address
        self[:building] = setting(:building)
        self[:level] = setting(:level)

        @reserve_time = setting(:reserve_time) || 0
    end

    def on_unload
        @transport&.close
        @transport = nil

        td = ::Aca::TrapDispatcher.instance
        td.ignore(@resolved_ip) if @resolved_ip
    end

    def is_processing?
        "IP resolved to #{@resolved_ip}\ntransport online #{!!@transport}\nprocessing #{!!@transport&.request}"
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
        on_trap(ifIndex, state) if ifIndex && state
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
            remove_reserved(interface)
            @check_interface << interface
            @connected_interfaces << interface
        when :down
            logger.debug { "Notify Down: #{interface}" }
            remove_lookup(interface)
        end

        self[:interfaces] = @connected_interfaces.to_a
    end

    AddressType = {
        0  => :unknown,
        1  => :ipv4,
        2  => :ipv6,
        3  => :ipv4z,
        4  => :ipv6z,
        16 => :dns
    }.freeze

    AcceptAddress = [:ipv4, :ipv6, :ipv4z, :ipv6z].freeze

    BindingStatus = {
        1 => :active,
        2 => :not_in_service,
        3 => :not_ready,
        4 => :create_and_go,
        5 => :create_and_wait,
        6 => :destroy
    }.freeze

    # cdsBindingsEntry
    EntryParts = {
        '1' => :vlan,        # Cisco has made this not-accessible
        '2' => :mac_address, # Cisco has made this not-accessible
        '3' => :addr_type,
        '4' => :ip_address,
        '5' => :interface,
        '6' => :leased_time,    # in seconds
        '7' => :binding_status, # can set this to destroy to delete entry
        '8' => :hostname
    }.freeze

    SnoopingEntry = Struct.new(:id, *EntryParts.values) do
        def address_type
            AddressType[self.addr_type]
        end

        def mac
            self.mac_address || self.extract_vlan_and_mac.mac_address
        end

        def get_vlan
            self.vlan || self.extract_vlan_and_mac.vlan
        end

        def ip
            case self.address_type
            when :ipv4
                # DISPLAY-HINT "1d.1d.1d.1d"
                # Example response: "0A B2 C4 45"
                self.ip_address.split(' ').map { |i| i.to_i(16).to_s }.join('.')
            when :ipv6
                # DISPLAY-HINT "2x:2x:2x:2x:2x:2x:2x:2x"
                # IPAddr will present the IPv6 address in it's short form
                IPAddr.new(self.ip_address.gsub(' ', '').scan(/..../).join(':')).to_s
            end
        end

        def extract_vlan_and_mac
            parts = self.id.split('.')
            self.vlan = parts[0].to_i
            self.mac_address = parts[1..-1].map { |i| i.to_i.to_s(16).rjust(2, '0') }.join('')
            self
        end
    end

    # A row instance contains the Mac address, IP address type, IP address, VLAN number, interface number, leased time, and status of this instance.
    # http://www.oidview.com/mibs/9/CISCO-DHCP-SNOOPING-MIB.html
    # http://www.snmplink.org/OnLineMIB/Cisco/index.html#1634
    def query_snooping_bindings
        return :not_ready unless @transport
        return :currently_processing if @transport.request

        logger.debug 'extracting snooping table'

        # Walking cdsBindingsTable
        entries = {}
        @client.walk(oid: '1.3.6.1.4.1.9.9.380.1.4.1').each do |oid_code, value|
            part, entry_id = oid_code[28..-1].split('.', 2)
            next if entry_id.nil?

            entry = entries[entry_id] || SnoopingEntry.new
            entry.id = entry_id
            entry.__send__("#{EntryParts[part]}=", value)
            entries[entry_id] = entry
        end

        # Process the bindings
        entries = entries.values
        logger.debug { "found #{entries.length} snooping entries" }

        # Newest lease first
        entries = entries.reject { |e| e.leased_time.nil? }.sort { |a, b| b.leased_time <=> a.leased_time }

        checked = Set.new
        entries.each do |entry|
            interface = @if_mappings[entry.interface]
            next unless @check_interface.include?(interface)
            next if checked.include?(interface)

            mac = entry.mac
            ip = entry.ip
            next unless ::IPAddress.valid?(ip)

            checked << interface

            # NOTE:: Same as snooping_catalyst.rb
            iface = self[interface] || ::Aca::Tracking::StaticDetails.new

            if iface.ip != ip || iface.mac != mac
                logger.debug { "New connection on #{interface} with #{ip}: #{mac}" }

                # NOTE:: Same as username found
                details = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{@remote_address}-#{interface}") || ::Aca::Tracking::SwitchPort.new
                details.connected(mac, @reserve_time, {
                    device_ip: ip,
                    switch_ip: @remote_address,
                    hostname: @hostname,
                    switch_name: @switch_name,
                    interface: interface
                })

                # ip, mac, reserved?, clash?
                self[interface] = details.details

            elsif iface.username.nil?
                username = ::Aca::Tracking::SwitchPort.bucket.get("macuser-#{mac}", quiet: true)
                if username
                    logger.debug { "Found #{username} at #{ip}: #{mac}" }

                    # NOTE:: Same as new connection
                    details = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{@remote_address}-#{interface}") || ::Aca::Tracking::SwitchPort.new
                    details.connected(mac, @reserve_time, {
                        device_ip: ip,
                        switch_ip: @remote_address,
                        hostname: @hostname,
                        switch_name: @switch_name,
                        interface: interface
                    })

                    # ip, mac, reserved?, clash?
                    self[interface] = details.details
                end

            elsif !iface.reserved
                # We don't know the user who is at this desk...
                details = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{@remote_address}-#{interface}")
                reserved = details.check_for_user(@reserve_time)
                self[interface] = details.details if reserved

            elsif iface.clash
                # There was a reservation clash - is there still a clash?
                details = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{@remote_address}-#{interface}")
                details.check_for_user(@reserve_time)
                self[interface] = details.details unless details.clash?
            end
        end

        @connected_interfaces = checked
        self[:interfaces] = checked.to_a
        nil
    end

    # Index short name lookup
    # ifName: 1.3.6.1.2.1.31.1.1.1.1.xx  (where xx is the ifIndex)
    def query_index_mappings
        return :not_ready unless @transport
        return :currently_processing if @transport.request

        logger.debug 'mapping ifIndex to port names'
        @scheduled_if_query = false

        mappings = {}
        @client.walk(oid: '1.3.6.1.2.1.31.1.1.1.1').each do |oid_code, value|
            oid_code = oid_code[23..-1]
            mappings[oid_code.to_i] = value.downcase
        end

        logger.debug { "found #{mappings.length} ports" }

        @if_mappings = mappings
    end

    # ifOperStatus: 1.3.6.1.2.1.2.2.1.8.xx == up(1), down(2), testing(3)
    def query_interface_status
        return :not_ready unless @transport
        return :currently_processing if @transport.request

        logger.debug 'querying interface status'

        @client.walk(oid: '1.3.6.1.2.1.2.2.1.8').each do |oid_code, value|
            oid_code = oid_code[20..-1]
            interface = @if_mappings[oid_code.to_i]

            next unless interface

            case value
            when 1 # up
                next if @check_interface.include?(interface)
                logger.debug { "Interface Up: #{interface}" }
                if !@check_interface.include?(interface)
                    remove_reserved(interface)
                    @check_interface << interface
                end
            when 2 # down
                next unless @check_interface.include?(interface)
                logger.debug { "Interface Down: #{interface}" }
                remove_lookup(interface)
            else
                next
            end
        end
    end

    def query_connected_devices
        logger.debug 'Querying for connected devices'
        query_index_mappings if @if_mappings.empty? || @scheduled_if_query
        query_interface_status if @scheduled_status_query
        query_snooping_bindings
    end

    def update_reservations
        check_reservations
    end


    protected


    def new_client
        schedule.clear

        settings = setting(:snmp_options).to_h.symbolize_keys
        @transport&.close
        @transport = settings[:proxy] = Protocols::Snmp.new(self, setting(:response_timeout) || 7000)
        @transport.register(@resolved_ip, remote_port)
        @client = NETSNMP::Client.new(settings)
        @community = settings[:community]

        # Grab the initial state
        next_tick do
            query_connected_devices
        end

        # Connected device polling (in case a trap was dropped by the network)
        # Also expires any desk reservations every 1min
        schedule.every(57000 + rand(5000)) do
            query_connected_devices
            check_reservations if @reserve_time > 0
        end

        schedule.every('10m') { @scheduled_status_query = true }

        # There is a possibility that these will change on switch reboot
        schedule.every('15m') { @scheduled_if_query = true }
    end

    def received(data, resolve, command)
        logger.error "unexpected response:\n#{data.inspect}"
        :abort
    end

    def remove_lookup(interface)
        # We are no longer interested in this interface
        @check_interface.delete(interface)

        # Update the status of the switch port
        model = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{@remote_address}-#{interface}")
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

    def check_reservations
        remove = []

        # Check if the interfaces are still reserved
        @reserved_interface.each do |interface|
            details = ::Aca::Tracking::SwitchPort.find_by_id("swport-#{@remote_address}-#{interface}")
            remove << interface unless details.reserved?
            self[interface] = details.details
        end

        # Remove them from the reserved list if not
        return unless remove.present?

        @reserved_interface -= remove
        self[:reserved] = @reserved_interface.to_a
    end
end
