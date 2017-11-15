module Aca; end
module Aca::Tracking; end

class Aca::Tracking::DeskManagement
    include ::Orchestrator::Constants

    descriptive_name 'ACA Desk Management'
    generic_name :DeskManagement
    implements :logic

    def on_load
        on_update

        # Should only call once
        desk_usage
    end

    def on_update
        # { "switch_name": { "port_id": "desk_id" } }
        @interface_mappings = setting(:mappings) || {}
    end

    def get_usage(building, level)
        self["#{building}+#{level}"] || []
    end

    protected

    def switches
        system.all(:Snooping)
    end

    def desk_usage
        # Get local vars in case they change while we are processing
        all_switches = switches.to_a
        mappings = @interface_mappings

        # Perform operations on the thread pool
        @caching = thread.work {
            buildings = {}

            # Find the desks in use
            all_switches.each do |switch|
                apply_mappings(buildings, switch, mappings)
            end

            # Cache the levels
            buildings.each do |building, levels|
                levels.each do |level, desks|
                    self["#{building}+#{level}"] = desks
                end
            end
        }.finally {
            schedule.in('5s') { desk_usage }
        }
    end

    def apply_mappings(buildings, switch, mappings)
        map = mappings[switch[:name]]
        if map.nil?
            logger.debug { "no mapping for switch #{switch[:name]}" }
            return
        end

        # Grab switch information
        interfaces = switch[:interfaces]
        building = switch[:building]
        level = switch[:level]

        # Build lookup structures
        b = buildings[building] ||= {}
        inuse = b[level] ||= []

        # Map the ports to desk IDs
        interfaces.each do |port|
            desk_id = map[port]
            inuse << desk_id if desk_id
        end
    end
end
