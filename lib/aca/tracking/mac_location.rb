# frozen_string_literal: true

module Aca; end
module Aca::Tracking; end
class Aca::Tracking::MacLocation < CouchbaseOrm::Base
    design_document :macloc

    before_create :set_id

    attribute :mac_address, type: String  # MAC of the device connected to the switch
    attribute :device_ip,   type: String  # IP of the device connected to the switch
    attribute :switch_ip,   type: String  # IP of the network switch
    attribute :hostname,    type: String  # defined on switch
    attribute :switch_name, type: String  # defined in backoffice
    attribute :interface,   type: String  # the switch port this device is connected

    validates :switch_ip,   presence: true
    validates :interface,   presence: true
    validates :mac_address, presence: true
    validates_format_of :mac_address,
        :with => /(?:[[:xdigit:]]{1,2}([-:]))(?:[[:xdigit:]]{1,2}\1){4}[[:xdigit:]]{1,2}/,
        :on => :create

    # self.find_by_switch_ip(ip)
    index_view :switch_ip


    protected


    def set_id
        self.id = "macloc-#{self.mac_address.downcase}"
    end
end
