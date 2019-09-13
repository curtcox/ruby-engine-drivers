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
        @desk_ids = setting('sensor_name_to_desk_mappings') || {}

        @subscriptions ||= []
        @subscriptions.each { |ref| unsubscribe(ref) }
        @subscriptions.clear

        # Initialize all zone status variables to [] or 0, but keep existing values if they exist (||=)
        all_zone_ids = @sensors.values.flatten.compact.uniq
        all_zone_ids.each do |z|
            self[z] ||= []                     # occupied (busy) desk ids in this zone
            self[z+':desk_ids']       ||= []   # all desk ids in this zone
            self[z+':occupied_count'] ||= 0
            self[z+':desk_count']     ||= 0
        end

        @sensors.each do |sensor,zones|
            zones.each do |zone|
                # Populate our initial status with the current data from all given Sensors
                update_zone(zone, sensor)

                # Subscribe to live updates from the sensors
                device,index = sensor.split('_')
                @subscriptions << system.subscribe(device, index.to_i, :free_desks) do |notification|
                    update_zone(zone, sensor)
                end
            end
        end
    end

    # Update one zone with the current data from ONE sensor (there may be multiple sensors serving a zone)
    def update_zone(zone, sensor)
        # The below values reflect just this ONE sensor, not neccesarily the whole zone
        all_desks  = id system[sensor][:all_desks]
        busy_desks = id system[sensor][:busy_desks]
        free_desks = all_desks - busy_desks

        # add the desks from this sensor to the other sensors in the zone
        self[zone+':desk_ids'] = self[zone] | all_desks
        self[zone] = (self[zone] | busy_desks) - free_desks

        self[zone+':occupied_count'] = self[zone].count
        self[zone+':desk_count']     = self[zone+':desk_ids'].count
        self[:last_update] = Time.now.in_time_zone($TZ).to_s
    end

    # Grab the list of desk ids in use on a floor
    #
    # @param level [String] the level id of the floor
    def desk_usage(zone)
        self[zone] || []
    end


    # Since this driver cannot know which user is at which desk, just return nil
    # @param desk_id [String] the unique id that represents a desk
    def desk_details(*desk_ids)
        nil
    end

    protected

    def id(array)
        return [] if array.nil?
        array.map { |i| @desk_ids[i] || i } 
    end
end
