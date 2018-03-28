module Lutron; end

# Login #1: nwk
# Login #2: nwk2

class Lutron::Lighting
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 23
    descriptive_name 'Lutron Lighting Gateway'
    generic_name :Lighting

    # Communication settings
    tokenize delimiter: "\r\n"
    wait_response false
    delay between_sends: 100

    def on_load
    end

    def on_unload
    end

    def on_update
    end

    def connected
        schedule.every('60s') do
            logger.debug "-- Polling Lutron"
        end
    end

    def disconnected
        schedule.clear
    end

    # on or off
    def lighting(device, state, action = 1)
        level = is_affirmative?(state) ? 100 : 0
        light_level(device, level, 1, 0)
    end

    # light fading
    def light_level(device, level, action = 1, rate = 1000)
        level = in_range(level.to_i, 100)
        seconds = (rate.to_i / 1000).to_i
        min = seconds / 60
        seconds = seconds - (min * 60)
        time = "#{min.to_s.rjust(2, '0')}:#{seconds.to_s.rjust(2, '0')}"
        send_cmd 'OUTPUT', device, action, level, time
    end

    # recall a preset (button action)
    def trigger(area, action)
        # Level = 200–232 for Scene Number =0–32
        send_cmd 'AREA', area, 12, (action.to_i + 200)
    end

    def received(data, resolve, command)
        logger.debug { "Lutron sent: #{data}" }

        

        return :success
    end

    protected

    def send_cmd(*command, **options)
        cmd = "##{command.join(',')}"
        logger.debug { "Requesting: #{cmd}" }
        send("#{cmd}\r\n", options)
    end

    def send_query(*command, **options)
        cmd = "?#{command.join(',')}"
        logger.debug { "Requesting: #{cmd}" }
        send("#{cmd}\r\n", options)
    end
end
