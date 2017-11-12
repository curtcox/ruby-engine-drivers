# frozen_string_literal: true

module Aca; end
module Aca::Tracking; end

class Aca::Tracking::SwitchPort < CouchbaseOrm::Base
    design_document :swport

    attribute :connected,    type: Boolean
    attribute :mac_address,  type: String  # MAC of the device currently connected to the switch
    attribute :unplug_time,  type: Integer # Unlug time for timeout
    attribute :reserve_time, type: Integer # Length of time for the reservation
    attribute :reserved_mac, type: String
    belongs_to :reserved_by, class_name: 'User'

    attribute :device_ip,   type: String  # IP of the device connected to the switch
    attribute :switch_ip,   type: String  # IP of the network switch
    attribute :hostname,    type: String  # defined on switch
    attribute :switch_name, type: String  # defined in backoffice
    attribute :interface,   type: String  # the switch port this device is connected

    validates :switch_ip,   presence: true
    validates :interface,   presence: true

    # self.find_by_switch_ip(ip) => Enumerator
    index_view :switch_ip

    # self.find_by_mac_address(mac) => nil or SwitchPort
    index :mac_address, presence: false
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
    def connected(mac_address)
        self.connected = true
        self.mac_address = mac_address
        self.save!

        # Return true if desk is reserved
        ((self.unplug_time || 0) + (self.reserve_time || 0)) > Time.now.to_i
    end

    def reserve(time)
        return unless self.reserved_mac

        now = Time.now.to_i
        reserved = if self.connected
            ((self.unplug_time || 0) + (self.reserve_time || 0)) > now
        else
            !!self.reserved_mac
        end

        if reserved
            self.reserve_time = time.to_i
            self.save!
        end

        # Was the reservation request successful
        reserved
    end

    def disconnected(reserve_time = 5.minutes)
        return false unless self.connected
        self.connected = false

        now = Time.now.to_i
        if ((self.unplug_time || 0) + (self.reserve_time || 0)) < now
            self.unplug_time = now
            self.reserve_time = reserve_time
            self.reserved_mac = self.mac_address
        end
        self.mac_address = nil
        self.save!

        # Ask user if they would like to reserve the desk
        self.reserve_time > 0 && now == self.unplug_time 
    end


    protected


    before_create :set_id
    def set_id
        self.id = "swport-#{self.switch_ip}-#{interface}"
    end
end
