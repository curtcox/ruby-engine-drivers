# encoding: ASCII-8BIT
# frozen_string_literal: true

module Ricoh; end

class Ricoh::D6500
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 50915 # Need to go through an RS232 gatway
    descriptive_name 'Ricoh D6500 Interactive Whiteboard'
    generic_name :Display

    # Communication settings
    tokenize indicator: "\+", delimiter: "\r"

    default_settings(
        id: '02'
    )

    def on_load
        self[:volume_min] = 0
        self[:volume_max] = 100
        on_update
    end

    def on_update
        self[:id] = setting(:id)
    end

    def on_unload; end

    def connected; end

    def disconnected
        # Disconnected will be called before connect if initial connect fails
        schedule.clear
    end

    def power(state)
        target = is_affirmative?(state)
        self[:power_target] = target

        # Execute command
        logger.debug { "Target = #{target} and self[:power] = #{self[:power]}" }
        if target == On && self[:power] != On
            send_cmd("#{COMMANDS[:power]}#{prepend('001')}", name: :power_cmd)
        elsif target == Off && self[:power] != Off
            send_cmd("#{COMMANDS[:power]}#{prepend('000')}", name: :power_cmd)
        end
    end

    def power?
        send_inq(COMMANDS[:power_inq], name: :power_inq)
    end

    INPUTS = {
        vga: '000',
        hdmi: '001',
        hdmi2: '002',
        av: '003',
        ypbpr: '004',
        svideo: '005',
        dvi: '006',
        display_port: '007',
        sdi: '008',
        multimedia: '009',
        network: '010',
        usb: '011'
    }.freeze
    def switch_to(input)
        self[:input_target] = input
        input = input.to_sym if input.class == String
        send_cmd("#{COMMANDS[:input]}#{prepend(INPUTS[input])}", name: :input_cmd)
    end

    def input?
        send_inq(COMMANDS[:input_inq], name: :input_inq)
    end

    AUDIO_INPUTS = {
        audio: '000',
        audio2: '001',
        hdmi: '002',
        hdmi2: '003',
        display_port: '004',
        sdi: '005',
        multimedia: '006'
    }.freeze
    def switch_audio(input)
        self[:audio] = input
        input = input.to_sym if input.class == String
        send_cmd("#{COMMANDS[:audio]}#{prepend(AUDIO_INPUTS[input])}", name: :audio_cmd)
    end

    def audio?
        send_inq(COMMANDS[:audio_inq], name: :audio_inq)
    end

    def volume(vol)
        val = in_range(vol, self[:volume_max], self[:volume_min])
        self[:volume_target] = val
        val = val.to_s.rjust(3, '0')
        logger.debug("volume = #{prepend(val)}")
        send_cmd("#{COMMANDS[:volume]}#{prepend(val)}", name: :volume_cmd)
    end

    def volume?
        send_inq(COMMANDS[:volume_inq], name: :volume_inq)
    end

    def mute(state)
        target = is_affirmative?(state)
        self[:mute_target] = target

        # Execute command
        logger.debug { "Target = #{target} and self[:mute] = #{self[:mute]}" }
        if target == On && self[:mute] != On
            send_cmd("#{COMMANDS[:mute]}#{prepend('001')}", name: :mute_cmd)
        elsif target == Off && self[:mute] != Off
            send_cmd("#{COMMANDS[:mute]}#{prepend('000')}", name: :mute_cmd)
        end
    end

    def mute?
        send_inq(COMMANDS[:mute_inq], name: :mute_inq)
    end

    COMMANDS = {
        power_cmd: '21',
        input_cmd: '22',
        volume_cmd: '35',
        mute_cmd: '36',
        audio_cmd: '88',
        power_inq: '6C',
        input_inq: '6A',
        volume_inq: '66',
        mute_inq: '67',
        audio_inq: '88'
    }.freeze
    def send_cmd(cmd, options = {})
        req = "3#{get_length(cmd)}3#{self[:id][0]}3#{self[:id][1]}73#{cmd}0D"
        logger.debug("tell -- 0x#{req} -- #{options[:name]}")
        options[:hex_string] = true
        send(req, options)
    end

    def send_inq(inq, options = {})
        req = "3#{get_length(cmd)}3#{self[:id][0]}3#{self[:id][1]}67#{cmd}#{prepend('000')}0D"
        logger.debug("ask -- 0x#{req} -- #{options[:name]}")
        options[:hex_string] = true
        send(req, options)
    end

    def received(data, deferrable, command)
        hex = byte_to_hex(data)
        return :success if command.nil? || command[:name].nil?

        case command[:name]
        when :power_cmd
            self[:power] = self[:power_target] if true
        when :power_inq
            self[:power] = On if hex == "80000080"
            self[:power] = Off if hex == "80010081"
        when :input
            self[:input] = INPUTS_INQ[hex]
        when :volume
            self[:volume] = byte_to_hex(data[-2]).to_i(16)
        when :mute
            self[:mute] = On if hex == "82010083"
            self[:mute] = Off if hex == "82010184"
        end

        logger.debug { "Received 0x#{hex}\n" }
    end

    def get_length(req)
        # req only contains value which is 3 bytes
        # 2 bytes for id
        # 1 byte for cmd type
        # 1 byte for cmd code
        # 1 byte for delimiter
        req.length / 2 + 5
    end

    def prepend(str)
        str = str.to_s if str.class != String
        joined = ''
        str.each_char do |c|
            joined += "3#{c}"
        end
        joined
    end
end
