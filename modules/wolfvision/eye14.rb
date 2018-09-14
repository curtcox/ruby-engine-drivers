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
            logger.debug "-- Polling Sony Camera"
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

        # Execute command
        logger.debug { "Target = #{target} and self[:power] = #{self[:power]}" }
        if target == On && self[:power] != On
            send_cmd("300101", name: :power_cmd)
        elsif target == Off && self[:power] != Off
            send_cmd("300100", name: :power_cmd)
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
        send_inq("2000", priority: 0, name: :zoom_inq)
    end

    # set autofocus to on
    def autofocus
        send_cmd("310101", name: :autofocus_cmd)
    end

    def autofocus?
        send_inq("3100", priority: 0, name: :autofocus_inq)
    end

    def iris(position)
        val = in_range(position, self[:iris_max], self[:iris_min])
        self[:iris_target] = val
        logger.debug { "position in decimal is #{val}" }
        logger.debug { "hex is #{val.to_s(16).rjust(4, '0')}" }
        send_cmd("2202#{val.to_s(16).rjust(4, '0')}", name: :iris_cmd)
    end

    def iris?
        send_inq("2200", priority: 0, name: :iris_inq)
    end

    def power?
        send_inq("3000", priority: 0, name: :power_inq)
    end

    def laser(state)
        target = is_affirmative?(state)
        self[:laser_target] = target

        # Execute command
        logger.debug { "Target = #{target} and self[:laser] = #{self[:laser]}" }
        if target == On && self[:laser] != On
            send_cmd("A70101", name: :laser_cmd)
        elsif target == Off && self[:laser] != Off
            send_cmd("A70100", name: :laser_cmd)
        end
    end

    def laser?
        send_inq("A700", priority: 0, name: :laser_inq)
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

    def received(data, deferrable, command)
        logger.debug { "Received 0x#{byte_to_hex(data)}\n" }

        bytes = str_to_array(data)

        return :success if command.nil? || command[:name].nil?
        case command[:name]
        when :power_cmd
            self[:power] = self[:power_target] if byte_to_hex(data) == "3000"
        when :zoom_cmd
            self[:zoom] = self[:zoom_target] if byte_to_hex(data) == "2000"
        when :iris_cmd
            self[:iris] = self[:iris_target] if byte_to_hex(data) == "2200"
        when :autofocus_cmd
            self[:autofocus] = true if byte_to_hex(data) == "3100"
        when :power_inq
            # -1 index for array refers to the last element in Ruby
            self[:power] = bytes[-1] == 1
        when :zoom_inq
            # for some reason the after changing the zoom position
            # the first zoom inquiry sends "2000" regardless of the actaul zoom value
            # consecutive zoom inquiries will then return the correct zoom value
            return :ignore if byte_to_hex(data) == "2000"
            hex = byte_to_hex(data[-2..-1])
            self[:zoom] = hex.to_i(16)
        when :autofocus_inq
            self[:autofocus] = bytes[-1] == 1
        when :iris_inq
            # same thing as zoom inq happens here
            return :ignore if byte_to_hex(data) == "2200"
            hex = byte_to_hex(data[-2..-1])
            self[:iris] = hex.to_i(16)
        when :laser_cmd
            self[:laser] = self[:laser_target] if byte_to_hex(data) == "a700"
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
