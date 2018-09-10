module Elo; end

# Documentation: https://docs.elotouch.com/collateral/ELO_APP_Notes_17084AEB00033_Web.pdf

class Elo::Display4202L
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 7000
    descriptive_name 'Elo 4202L'
    generic_name :Display

    tokenize indicator: /ack|ACK/, delimiter: "\x0D"

    def on_load
        on_update
    end

    def on_update

    end

    def connected
        do_poll
        schedule.every('60s') do
            logger.debug "-- Polling Display"
            do_poll
        end
    end

    def disconnected
        schedule.clear
    end

    def do_poll
        power? do
            if self[:power]
                input?
            end
        end
    end
end
