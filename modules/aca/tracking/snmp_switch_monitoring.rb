# frozen_string_literal: true
# encoding: ASCII-8BIT

module Aca; end
module Aca::Tracking; end

class Aca::Tracking::SnmpSwitchMonitoring
    include ::Orchestrator::Constants

    descriptive_name 'ACA SNMP Switch Monitoring'
    generic_name :SNMP_Trap
    implements :logic

    def on_load
        on_update
    end

    def on_update
        # Ensure server is stopped
        on_unload
        configure_server
    end

    def on_unload
        if @server
            @server.close
            @server = nil

            # Stop the server if started
            logger.info "server stopped"
        end
    end

    protected

    def configure_server
        port = setting(:port) || 162

        @server = thread.udp { |data, ip, port|
            process(data, ip, port)
        }.bind('0.0.0.0', port).start_read

        logger.info "trap server started"
    end

    def process(data, ip, port)

    end
end
