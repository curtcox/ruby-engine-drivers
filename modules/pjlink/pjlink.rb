# frozen_string_literal: true
# encoding: ASCII-8BIT
module Pjlink; end

# Documentation: https://pjlink.jbmia.or.jp/english/data_cl2/PJLink_5-1.pdf

class Pjlink::Pjlink
    include ::Orchestrator::Constants

    # Discovery Information
    tcp_port 4352
    descriptive_name 'Projector with Pjlink control'
    generic_name :Display

    # Communication settings
    # 24bytes with header however we'll ignore the footer
    tokenize indicator: "%1", delimiter: "\x0D"

    def on_load
        self[:volume_min] = 0
        self[:volume_max] = 100
    end

    def connected
        poll
        schedule.every('5s') { poll }
    end

    def disconnected
        # Stop polling
        schedule.clear
    end

    INPUTS = {
        hdmi: '31',
        hdmi2: '32',
        hdmi3: '33',
        vga: '11',
        vga2: '12',
        vga3: '13',
        usb: '41',
        network: '51'
    }
    LOOKUP_INPUTS = INPUTS.invert

    def switch_to(input)
        logger.debug { "requesting to switch to: #{input}" }
        do_send(COMMANDS[:input], INPUTS[input])
        input?
    end

    def power(state, _ = nil)
        do_send(COMMANDS[:power], state ? '1' : '0')
    end

    def mute(state = true)
        do_send(COMMANDS[:mute], state ? '31' : '30')
    end
    def unmute
        mute false
    end

    def video_mute(state = true)
        do_send(COMMANDS[:mute], state ? '11' : '10')
    end
    def video_unmute
        mute false
    end

    def audio_mute(state = true)
        do_send(COMMANDS[:mute], state ? '21' : '20')
    end
    def audio_unmute
        mute false
    end

    def poll
        power? do
            if self[:power]
                input?
                mute?
                volume?
            end
        end
    end

    protected

    COMMANDS = {
      power: 'POWR',
      mute: 'AVMT',
      input: 'INPT',
      error_status: 'ERST',
      lamp: 'LAMP',
      name: 'NAME1'
    }
    LOOKUP_COMMANDS = COMMANDS.invert

    COMMANDS.each do |name, pj_cmd|
      define_method "#{name}?" do
        do_query pj_cmd
      end
    end

    def do_query(command, **options)
        cmd = "%1#{command} ?\x0D"
        send(cmd, options)
    end

    def do_send(command, parameter, **options)
        cmd = "%1#{command} #{parameter}\x0D"
        send(cmd, options)
    end

    def received(data, resolve, command)
        logger.debug { "sent: #{data}" }
        cmd, param = parse_response(data).values_at(:cmd, :param)

        return :abort if param =~ /^ERR/
        return :success if param == 'OK'

        update_status(cmd, param)
        return :success
    end

 #      0123456789
 # e.g. NAME=Test Projector
    def parse_response(byte_str)
        {
            cmd: LOOKUP_COMMANDS[byte_str[0..4]],
            param: byte_str[5..-1]
        }
    end

    # Update module state based on device feedback
    def update_status(cmd, param)
        case cmd.to_sym
        when :power, :mute, :audio_mute, :video_mute
            self[cmd] = param == '1'
        when :volume
            self[:volume] = param.to_i
        when :input
            self[:input] = LOOKUP_INPUTS[param]
        end
    end
end
