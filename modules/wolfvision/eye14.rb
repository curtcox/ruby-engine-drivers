# encoding: ASCII-8BIT
# frozen_string_literal: true

module Wolfvision; end

# Documentation: https://www.wolfvision.com/wolf/protocol_command_wolfvision/protocol/commands_eye-14.pdf

class Wolfvision::Eye14
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 50915 # Need to go through an RS232 gatway
    descriptive_name 'WolfVision EYE-14'
    generic_name :Camera

    # Communication settings
    tokenize indicator: /\x00|\x01|/, callback: :check_length
    delay between_sends: 150

    def on_load
        self[:zoom_max] = 3923
        self[:iris_max] = 4094
        self[:zoom_min] = self[:iris_min] = 0
        on_update
    end

    def on_update
    end

    def on_unload
    end

    def connected
        schedule.every('60s') do
            logger.debug '-- Polling WolfVision Camera'
            power? do
                if self[:power] == On
                    zoom?
                    iris?
                    autofocus?
                end
            end
        end
    end

    def disconnected
        # Disconnected will be called before connect if initial connect fails
        schedule.clear
    end

    def power(state)
        target = is_affirmative?(state)
        self[:power_target] = target
        if target == On && self[:power] != On
            send_cmd('300101', name: :power_cmd)
        elsif target == Off && self[:power] != Off
            send_cmd('300100', name: :power_cmd)
        end
    end

    # uses only optical zoom
    def zoom(position)
        val = in_range(position, self[:zoom_max], self[:zoom_min])
        self[:zoom_target] = val
        logger.debug { "position in decimal is #{val}" }
        logger.debug { "hex is #{val.to_s(16).rjust(4, '0')}" }
        send_cmd("2002#{val.to_s(16).rjust(4, '0')}", name: :zoom_cmd)
    end

    def zoom?
        send_inq('2000', priority: 0, name: :zoom_inq)
    end

    # set autofocus to on
    def autofocus
        send_cmd('310101', name: :autofocus_cmd)
    end

    def autofocus?
        send_inq('3100', priority: 0, name: :autofocus_inq)
    end

    def iris(position)
        val = in_range(position, self[:iris_max], self[:iris_min])
        self[:iris_target] = val
        logger.debug { "position in decimal is #{val}" }
        logger.debug { "hex is #{val.to_s(16).rjust(4, '0')}" }
        send_cmd("2202#{val.to_s(16).rjust(4, '0')}", name: :iris_cmd)
    end

    def iris?
        send_inq('2200', priority: 0, name: :iris_inq)
    end

    def power?
        send_inq('3000', priority: 0, name: :power_inq)
    end

    def laser(state)
        target = is_affirmative?(state)
        self[:laser_target] = target
        if target == On && laser_status != On
            send_cmd('A70101', name: :laser_cmd)
        elsif target == Off && laser_status != Off
            send_cmd('A70100', name: :laser_cmd)
        end
    end

    def laser?
        send_inq('A700', priority: 0, name: :laser_inq)
    end

    def send_cmd(cmd, options = {})
        req = "01#{cmd}"
        logger.debug { "tell -- 0x#{req} -- #{options[:name]}" }
        options[:hex_string] = true
        send(req, options)
    end

    def send_inq(inq, options = {})
        req = "00#{inq}"
        logger.debug { "ask -- 0x#{inq} -- #{options[:name]}" }
        options[:hex_string] = true
        send(req, options)
    end

    COMMANDS = {
        '3000' => :power_cmd,
        '3001' => :power_inq,
        '2000' => :zoom_cmd,
        '2002' => :zoom_inq,
        '2200' => :iris_cmd,
        '2202' => :iris_inq,
        '3100' => :autofocus_cmd,
        '3101' => :autofocus_inq,
        'a700' => :laser_cmd,
        'a701' => :laser_inq
    }
    def received(data, deferrable, command)
        logger.debug { "Received 0x#{byte_to_hex(data)}\n" }

        bytes = str_to_array(data)

        return :success if command.nil? || command[:name].nil?

        cmd = COMMANDS[byte_to_hex(data)[0..3]]

        case cmd
        when :power_cmd
            self[:power] = self[:power_target]
        when :power_inq
            self[:power] = bytes[-1] == 1
        when :zoom_cmd
            # for some reason the after changing the zoom position
            # the first zoom inquiry sends "2000" regardless of the actaul zoom value
            # consecutive zoom inquiries will then return the correct zoom value
            return :ignore if command[:name] == :zoom_inq
            self[:zoom] = self[:zoom_target]
        when :zoom_inq
            hex = byte_to_hex(data[-2..-1])
            self[:zoom] = hex.to_i(16)
        when :iris_cmd
            return :ignore if command[:name] == :iris_inq
            self[:iris] = self[:iris_target]
        when :iris_inq
            # same thing as zoom inq happens here
            hex = byte_to_hex(data[-2..-1])
            self[:iris] = hex.to_i(16)
        when :autofocus_cmd
            self[:autofocus] = true
        when :autofocus_inq
            self[:autofocus] = bytes[-1] == 1
        when :laser_cmd
            self[:laser] = self[:laser_target]
        when :laser_inq
            self[:laser] = bytes[-1] == 1
        end
        return :success
    end

    def check_length(byte_str)
        response = str_to_array(byte_str)

        return false if response.length <= 1 # header is 2 bytes

        len = response[1] + 2 # (data length + header)

        if response.length >= len
            return len
        else
            return false
        end
    end
end
