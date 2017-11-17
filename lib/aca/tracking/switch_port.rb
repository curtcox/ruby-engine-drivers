# frozen_string_literal: true

module Aca; end
module Aca::Tracking; end

class Aca::Tracking::SwitchPort < CouchbaseOrm::Base
    design_document :swport

    # Connection details
    attribute :mac_address, type: String  # MAC of the device currently connected to the switch
    attribute :device_ip,   type: String  # IP of the device connected to the switch

    # Reservation details
    attribute :unplug_time,  type: Integer # Unlug time for timeout
    attribute :reserve_time, type: Integer # Length of time for the reservation
    attribute :reserved_mac, type: String
    attribute :reserved_by,  type: String

    # Switch details
    attribute :switch_ip,   type: String  # IP of the network switch
    attribute :hostname,    type: String  # defined on switch
    attribute :switch_name, type: String  # defined in backoffice
    attribute :interface,   type: String  # the switch port this device is connected

    validates :switch_ip,   presence: true
    validates :interface,   presence: true

    # self.find_by_switch_ip(ip) => Enumerator
    index_view :switch_ip

    # self.find_by_mac_address(mac) => nil or SwitchPort
    index :mac_address,  presence: false
    index :reserved_mac, presence: false

    def self.locate(mac)
        port = ::Aca::Tracking::SwitchPort.find_by_mac_address(mac)
        return port if port

        port = ::Aca::Tracking::SwitchPort.find_by_reserved_mac(mac)
        return port if port && (port.unplug_time + port.reserve_time) >= Time.now.to_i

        nil
    end

    # ================
    # EVENT PROCESSING
    # ================

    # A new device has connected to the switch port
    def connected(mac_address, **switch_details)
        reserved = reserved?

        if not reserved
            self.unplug_time = 0
            self.reserve_time = 0
            self.reserved_mac = nil
            self.reserved_by = nil
        end
        self.mac_address = mac_address
        self.assign_attributes(switch_details)
        self.save!(with_cas: true)

        reserved
    rescue ::Libcouchbase::Error::KeyExists
        self.reload
        retry
    end

    # Change the owner of the desk to this new user
    def set_user(user, default_reserve_time = 5.minutes)
        self.reserved_by = user
        self.reserve_time = default_reserve_time.to_i
        self.reserved_mac = self.mac_address
        self.save!(with_cas: true)
    rescue ::Libcouchbase::Error::KeyExists
        self.reload
        retry
    end

    # Update the reservation (user would like to extend their desk booking)
    def update_reservation(time)
        return false unless self.reserved_mac

        reserved = if connected?
            # If the reserved time has expired then the current connected
            # user is the new owner of the desk
            reserved?
        else
            # Otherwise we can only reserve a desk if the user had been set
            !!self.reserved_mac
        end
        self.update_columns(reserve_time: time.to_i, with_cas: true) if reserved

        # Was the reservation request successful
        reserved
    rescue ::Libcouchbase::Error::KeyExists
        self.reload
        retry
    end

    def disconnected
        return false unless connected?

        # Configure pre-defined reservation on disconnect
        now = Time.now.to_i
        self.unplug_time = now if !reserved?
        self.mac_address = nil
        self.device_ip = nil
        self.save!(with_cas: true)

        # Ask user if they would like to reserve the desk
        self.reserve_time > 0 && now == self.unplug_time
    rescue ::Libcouchbase::Error::KeyExists
        self.reload
        retry
    end

    def reserved?
        ((self.unplug_time || 0) + (self.reserve_time || 0)) >= Time.now.to_i
    end

    def connected?
        !!self.mac_address
    end


    protected


    before_create :set_id
    def set_id
        self.id = "swport-#{self.switch_ip}-#{interface}"
    end
end
