module Shure; end
module Shure::Microphone; end

# Documentation: https://aca.im/driver_docs/Shure/MXA910+command+strings.pdf

class Shure::Microphone::Mxa
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 2202
    descriptive_name 'Shure Microflex MXA'
    generic_name :CeilingMic

    tokenize indicator: '< ', delimiter: ' >'

    default_settings({
        send_meter_levels: false
    })

    
    def on_load
        on_update
    end

    def on_update
    end

    def connected
        set_meter_rate(0) unless setting(:send_meter_levels)
        schedule.every('60s') do
            logger.debug "-- polling"
            do_poll
        end
    end

    def disconnected
        schedule.clear
    end

    def get_device_id
        do_send 'GET DEVICE_ID'
    end

    def set_meter_rate(rate)
        do_send 'SET METER_RATE', rate.to_s
    end

    # Mute commands
    def query_mute
        do_send 'GET DEVICE_AUDIO_MUTE'
    end

    def mute(val = true)
        state = is_affirmative?(val) ? 'ON' : 'OFF'
        do_send 'SET DEVICE_AUDIO_MUTE', state, name: :mute
    end

    def unmute
        mute false
    end

    # Preset commands
    def query_preset
        do_send 'GET PRESET'
    end

    def preset(number)
        do_send "SET PRESET #{number}", name: :preset
    end

    # flash the LED for 30 seconds
    def flash
        'SET FLASH ON'
    end

    def received(data, resolve, command)
        logger.debug { "-- received: #{data}" }

        resp = data.split(' ')
        case resp[0]
        when 'REP'
            key = resp[1].downcase.to_sym
            case key
            when :meter_rate, :preset
                self[key] = resp[2].to_i
            when :device_audio_mute
                self[:muted] = resp[2] == 'ON'
            else
                self[key] = resp[2]&.downcase
            end
        when 'SAMPLE'
            resp[1..-1].each_with_index do |level, index|
                self["output#{index + 1}"] = level.to_i
            end
        end

        return :success
    end

    def do_poll
        get_device_id
    end


    private


    def do_send(*command, **options)
        cmd = command.join(' ')
        logger.debug { "-- sending: < #{cmd} >" }
        send("< #{cmd} >", options)
    end
end
