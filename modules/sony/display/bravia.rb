# frozen_string_literal: true
# encoding: ASCII-8BIT

module Sony; end
module Sony::Display; end

# Documentation: https://aca.im/driver_docs/Sony/sony+bravia+simple+ip+control.pdf

class Sony::Display::Bravia
    include ::Orchestrator::Constants

    # Discovery Information
    tcp_port 20060
    descriptive_name 'Sony Bravia LCD Display'
    generic_name :Display

    # Communication settings
    # 24bytes with header however we'll ignore the footer
    tokenize indicator: "\x2A\x53", msg_length: 21

    def on_load # :nodoc:
        self[:volume_min] = 0
        self[:volume_max] = 100
    end

    def connected # :nodoc:
        # Display disconnects after 30seconds of no comms
        schedule.every('20s') { poll }
    end

    def disconnected # :nodoc:
        # Stop polling
        schedule.clear
    end
    
    # Power the display on or off
    #
    # @param [Boolean] the desired power state
    def power(state, _ = nil)
        if is_affirmative?(state)
            request(:power, 1)
            logger.debug "-- sony display requested to power on"
        else
            request(:power, 0)
            logger.debug "-- sony display requested to power off"
        end

        # Request status update
        power?
    end

    # query display power state
    def power?(**options, &block)
        options[:emit] = block if block_given?
        options[:priority] ||= 0
        query(:power, options)
    end

    INPUTS = {
        tv:     "00000",
        hdmi:   "10000",
        mirror: "50000",
        vga:    "60000"
    }
    INPUTS.merge!(INPUTS.invert)

    # switch to input on display
    #
    # @param [Symbol, String] the desired power state. i.e. hdmi2
    def switch_to(input)
        type, index = input.to_s.scan /[^0-9]+|\d+/
        index ||= '1'

        inp = type.to_sym
        raise ArgumentError, "unknown input #{input}" unless INPUTS.has_key? inp

        request(:input, "#{INPUTS[inp]}#{index.rjust(4, '0')}")
        logger.debug { "requesting to switch to: #{input}" }

        input?
    end

    def input?
        query(:input, priority: 0)
    end


    # Set the picture mute state
    #
    # @param [Boolean] the desired picture mute state
    def mute(state = true)
        val = is_affirmative?(state) ? 1 : 0
        request(:mute, val)
        logger.debug "requested to mute #{state}"
        mute?
    end

    def unmute
        mute false
    end

    def mute?
        query(:mute, priority: 0)
    end

    # Set the audio mute state
    #
    # @param [Boolean] the desired mute state
    def mute_audio(state = true)
        val = is_affirmative?(state) ? 1 : 0
        request(:audio_mute, val)
        logger.debug "requested to mute audio #{state}"
        audio_mute?
    end

    def unmute_audio
        mute_audio false
    end

    def audio_mute?
        query(:audio_mute, priority: 0)
    end

    # Set the volume to the desired level
    #
    # @param [Integer] the desired volume level
    def volume(level)
        request(:volume, level.to_i)
        volume?
    end

    def volume?
        query(:volume, priority: 0)
    end

    # Queries for power, input, mute, audio mute and volume state
    def poll
        power? do
            if self[:power]
                input?
                mute?
                audio_mute?
                volume?
            end
        end
    end

    def received(byte_str, resolve, command) # :nodoc:
        logger.debug { "sent: #{byte_str}" }

        type = TYPES[byte_str[0]]
        cmd = byte_str[1..4]
        param = byte_str[5..-1]

        # Request failure
        return :abort if param[0] == 'F'

        # If this is a response to a control request then it must have succeeded
        return :success if type == :answer && command && TYPES[command[:data][2]] == :control

        # Data request response or notify
        cmd_type = COMMANDS[cmd]
        case cmd_type
        when :power, :mute, :audio_mute, :pip
            self[cmd_type] = param.to_i == 1
        when :volume
            self[:volume] = param.to_i
        when :mac_address
            self[:mac_address] = param.split('#')[0]
        when :input
            input_num = param[7..11]
            index_num = param[12..-1].to_i
            if index_num == 1
                self[:input] = INPUTS[input_num]
            else
                self[:input] = :"#{INPUTS[input_num]}#{index_num}"
            end
        end

        # Ignore notify as we might be expecting a response and don't want to process 
        return :ignore if type == :notify
        :success
    end


    protected


    COMMANDS = {
        ir_code: 'IRCC',
        power: 'POWR',
        volume: 'VOLU',
        audio_mute: 'AMUT',
        mute: 'PMUT',
        channel: 'CHNN',
        tv_input: 'ISRC',
        input: 'INPT',
        toggle_mute: 'TPMU',
        pip: 'PIPI',
        toggle_pip: 'TPIP',
        position_pip: 'TPPP',
        broadcast_address: 'BADR',
        mac_address: 'MADR'
    }
    COMMANDS.merge!(COMMANDS.invert)

    TYPES = {
        control: "\x43",
        enquiry: "\x45",
        answer: "\x41",
        notify: "\x4E"
    }
    TYPES.merge! TYPES.invert

    def request(command, parameter = nil, **options) # :nodoc:
        cmd = command.to_sym
        options[:name] = cmd
        do_send(:control, COMMANDS[cmd], parameter, options)
    end

    def query(state, **options) # :nodoc:
        options[:name] = :"#{state}_query"
        do_send(:enquiry, COMMANDS[state.to_sym], nil, options)
    end

    def do_send(type, command, parameter = nil, **options) # :nodoc:
        param = parameter.nil? ? '################' : parameter.to_s.rjust(16, '0')
        cmd = "\x2A\x53#{TYPES[type]}#{command}#{param}\n"
        send(cmd, options)
    end
end
