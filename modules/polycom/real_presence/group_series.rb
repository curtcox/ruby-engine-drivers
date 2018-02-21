# encoding: ASCII-8BIT
# frozen_string_literal: true

module Polycom; end
module Polycom::RealPresence; end

class Polycom::RealPresence::GroupSeries
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security

    # Communication settings
    tokenize delimiter: "\r\n"
    delay between_sends: 200
    tcp_port 24

    # Discovery Information
    descriptive_name 'Polycom RealPresence Group Series'
    generic_name :VidConf


    def on_load
        on_update
    end

    def on_update

    end

    def connected
        register
        schedule.every('50s') do
            logger.debug 'Maintaining connection..'
            maintain_connection
        end
    end

    def disconnected
        schedule.clear
    end

    protect_method :reboot, :reset, :whoami, :unregister

    def reboot
        send "reboot now\r", name: :reboot
    end

    def reset
        send "resetsystem\r", name: :reset
    end

    def whoami
        send "whoami\r", name: :whoami
    end

    def unregister
        send "all unregister\r", name: :register
    end

    def register
        send "all register\r", name: :register
    end

    def maintain_connection
        # Queries the AMX beacon state.
        send "amxdd get\r", name: :connection_maintenance, priority: 0
    end

    def answer
        send "answer video\r", name: :answer
    end

    def notify(event)
        send "notify #{event}\r"
    end

    def nonotify(event)
        send "nonotify #{event}\r"
    end

    def received(response, resolve, command)
        logger.debug { "Polycom sent #{response}" }

        # Ignore the echo
        if command && command[:wait_count] == 0
            return :ignore
        end

        # Break up the message
        parts = response.split(/\s/)



        :success
    end
end
