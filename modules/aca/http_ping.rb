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

        # Don't update status on connection failure as we maintaining this
        config update_status: false
    end

    def check_status
        get(@path, name: :check_status) { |data|
            set_connected_state(data.status == @result)
        }.catch do
            set_connected_state(false)
        end
    end
end
