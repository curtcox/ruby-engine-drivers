# frozen_string_literal: true

module Shure; end
module Shure::Microphone; end

# Documentation: https://aca.im/driver_docs/Shure/MXA910+command+strings.pdf

class Shure::Microphone::Mxa
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    tcp_port 2202
    descriptive_name 'Shure Ceiling Array Microphone'
    generic_name :CeilingMic

    tokenize indicator: '< ', delimiter: ' >'

    def on_load
        on_update
    end

    def on_update; end

    def connected
        schedule.every('60s') do
            logger.debug '-- Polling Mics'
            do_poll
        end

        query_all
    end

    def disconnected
        schedule.clear
    end


    def query_all
        do_send 'GET 0 ALL'
    end

    def query_device_id
        do_send 'GET DEVICE_ID'
    end

    def query_firmware
        do_send 'GET FW_VER'
    end


    # Mute commands
    def query_mute
        do_send 'GET DEVICE_AUDIO_MUTE'
    end

    def mute(val = true)
        state = val ? 'ON' : 'OFF'
        do_send "SET DEVICE_AUDIO_MUTE #{state}", name: :mute
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
        do_send 'SET FLASH ON'
    end


    # LED Setup
    def query_led_state
        do_send 'GET DEV_LED_IN_STATE'
    end

    def led(on = true)
        state = on ? 'ON' : 'OFF'
        do_send "SET DEV_LED_IN_STATE #{state}", name: :led_state
    end

    def query_led_colour_muted
        do_send 'GET LED_COLOR_MUTED'
    end

    def led_colour_muted(colour)
        do_send "SET LED_COLOR_MUTED #{colour}"
    end

    def query_led_colour_unmuted
        do_send 'GET LED_COLOR_UNMUTED'
    end

    def led_colour_unmuted(colour)
        do_send "SET LED_COLOR_UNMUTED #{colour}"
    end

    def query_led_state_unmuted
        do_send 'GET LED_STATE_UNMUTED'
    end

    def led_state_unmuted(on = true)
        state = on ? 'ON' : 'OFF'
        do_send "SET LED_STATE_UNMUTED #{state}"
    end

    def query_led_state_muted
        do_send 'GET LED_STATE_MUTED'
    end

    def led_state_muted(on = true)
        state = on ? 'ON' : 'OFF'
        do_send "SET LED_STATE_MUTED #{state}"
    end

    def disco(enable = true)
        @disco = enable
    end


    def received(data, resolve, command)
        logger.debug { "-- received: #{data}" }

        resp = data.split(' ')
        param = resp[1].to_sym
        value = resp[2]

        return :abort if param == :ERR

        case param
        when :DEVICE_AUDIO_MUTE then self[:muted] = value == 'ON'
        when :PRESET then self[:preset] = value.to_i
        when :DEVICE_ID then self[:device_id] = value
        when :FIRMWARE then self[:firmware] = value
        when :DEV_LED_IN_STATE then self[:led_enabled] = value == 'ON'
        when :DEV_LED_STATE_MUTED then self[:led_muted] = value == 'ON'
        when :DEV_LED_STATE_UNMUTED then self[:led_unmuted] = value == 'ON'
        when :LED_COLOR_MUTED
            self[:led_colour_muted] = value.downcase.to_sym
        when :LED_COLOR_UNMUTED
            self[:led_colour_unmuted] = value.downcase.to_sym
        end

        if @disco
            if data =~ /AUTOMIX_GATE_OUT_EXT_SIG ON/
                led_colour_unmuted [:RED, :GREEN, :BLUE, :PINK, :PURPLE,
                                    :YELLOW, :ORANGE, :WHITE].sample
            end
        end

        :success
    end


    def do_poll
        get_device_id
    end


    private


    def do_send(command, options = {})
        logger.debug { "-- sending: < #{command} >" }
        send("< #{command} >", options)
    end
end
