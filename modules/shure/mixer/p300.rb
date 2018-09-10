module Elo; end

# Documentation: https://pubs.shure.com/guide/P300/en-US#c_c2b570b7-f7ef-444b-b01f-c1db82b064df

class Elo::Display4202L
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 2202
    descriptive_name 'Shure P300 IntelliMix Audio Conferencing Processor'
    generic_name :Mixer

    tokenize indicator: /ack|ACK/, delimiter: "\x0D"

    def on_load
        on_update

        self[:output_volume_max] = 1400
        self[:output_volume_min] = 0
    end

    def on_update
    end

    def connected
        do_poll
        schedule.every('60s') do
            do_poll
        end
    end

    def disconnected
        schedule.clear
    end

    def do_poll
    end

    def reboot
        send_cmd("REBOOT", name: :reboot)
    end

    def preset(number)
        send_cmd("PRESET #{number}", name: :present_cmd)
    end

    def preset?
        send_inq("PRESET", name: :preset_inq, priority: 0)
    end

    def flash_leds
        send_cmd("FLASH ON", name: :flash_cmd)
    end

    def volume(group, value)
        val = in_range(value, self[:zoom_max], self[:zoom_min])

        send_cmd("AUDIO_GAIN_HI_RES #{val.to_s.rjust(4, '0')}")
    end

    def volume?(group)
    end

    def mute(group, value = true)
        state = is_affirmative?(value) ? "ON" : "OFF"

        faders = group.is_a?(Array) ? group : [group]

        faders.each do |fad|
            send_cmd("#{fad} AUDIO_MUTE #{state}", group_type: :mute, wait: true)
        end
    end

    def unmute(group)
        mute(group, false)
    end

    def send_inq(cmd, options = {})
        req = "GET #{cmd}"
        logger.debug { "Sending: #{req}" }
        send(req, options)
    end

    def send_cmd(cmd, options = {})
        req = "SET #{cmd}"
        logger.debug { "Sending: #{req}" }
        send(req, options)
    end

    def received(data, deferrable, command)
        logger.debug { "Received: #{data}" }

        return :success if command.nil? || command[:name].nil?

        case command[:name]
        when :power
            self[:power] = data == 1
        when :input
            self[:input] = INPUT[data]
        end
        return :success
    end
end
