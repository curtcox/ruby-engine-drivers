module Aca; end

class Aca::HttpPing
    include ::Orchestrator::Constants

    implements :service
    descriptive_name 'Check if service is live'
    generic_name :HttpPing

    keepalive false

    def on_load
        schedule.every('60s') { check_status }
        on_update
    end

    def on_update
        @path = setting(:path) || '/'
        @result = setting(:result) || 200
    end

    def check_status
        get(@path) do |data|
            set_connected_state(data.status == @result)
        end
    end
end
