# frozen_string_literal: true

# Designed to work with Pressac Desk sensors (Pressac::Sensors::WsProtocol) and ACA staff app frontend
module Pressac; end
class ::Pressac::DeskManagement
    include ::Orchestrator::Constants

    descriptive_name 'Pressac Desk Bindings for ACA apps'
    generic_name :DeskManagement
    implements :logic

    default_settings({
        sensor_to_zone_mappings: {
            "Sensors_1" => ["zone-xxx"],
            "Sensors_2" => ["zone-xxx", "zone-zzz"]
        },
        sensor_name_to_desk_mappings: {
            "Note" => "This mapping is optional. If not present, the sensor NAME will be used and must match SVG map IDs",
            "Desk01" => "table-SYD.2.17.A",
            "Desk03" => "table-SYD.2.17.B"
        }
    })

    def on_load
        system.load_complete do
            begin
                on_update
            rescue => e
                logger.print_error e
            end
        end
    end

    def on_update
        @sensors = setting('sensor_to_zone_mappings') || {}
        @desks = setting('sensor_name_to_desk_mappings') || {}

        @subscriptions ||= []
        @subscriptions.each { |ref| unsubscribe(ref) }
        @subscriptions.clear
        
        @sensors.each do |sensor,zones|
            # Populate our initial status with the current data from all given Sensors
            zones.each do |zone|
                busy_desks = self[zone] ||= []
                all_desks  = self[zone + ":desk_ids"] ||= []
                #self[zone:desk_ids] is an array of all desks in this zone (zones may have multiple sensors)
                self[zone + ":desk_ids"] = all_desks | system[sensor][:all_desks].map{|d| @desks[d] || d}
                #self[zone] is an array of all occupied desks in this zone
                self[zone] = (self[zone] | system[sensor][:busy_desks].map{|d| @desks[d] || d}) - system[sensor][:free_desks].map{|d| @desks[d] || d}
            end
            # Subscribe to live updates from the sensors
            device,index = sensor.split('_')
            @subscriptions << system.subscribe(device, index.to_i, :busy_desks) do |notification|
                new_busy_desks = notification.value.map{|d| @desks[d]}
                new_free_desks = system[sensor][:free_desks].map{|d| @desks[d] || d} || []
                zones.each  { |zone| self[zone] = (self[zone] | new_busy_desks) - new_free_desks }
                zones.each  { |zone| self[zone + ":desk_ids"] = (self[zone + ":desk_ids"] | new_busy_desks) - new_free_desks }
            end
        end
    end

    protected

end
