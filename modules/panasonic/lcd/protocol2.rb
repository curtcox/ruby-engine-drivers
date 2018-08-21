require 'digest/md5'

module Panasonic; end
module Panasonic::LCD; end

class Panasonic::LCD::Protocol2
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 1024
    descriptive_name 'Panasonic LCD Protocol 2'
    generic_name :Display
    default_settings username: 'admin1', password: 'panasonic'

    # Communication settings
    tokenize delimiter: "\r", wait_ready: 'NTCONTROL'
    makebreak!

    # Projector will provide us with a password
    # Which is applied in before_transmit
    before_transmit :apply_password
    wait_response timeout: 5000, retries: 3

    def on_load
        @check_scheduled = false
        self[:power] = false
        self[:stable_state] = true  # Stable by default (allows manual on and off)

        # Meta data for inquiring interfaces
        self[:type] = :lcd

        # The projector drops the connection when there is no activity
        schedule.every('60s') do
            if self[:connected]
                power?(priority: 0).then do
                    volume? if self[:power]
                end
            end
        end

        on_update
    end

    def on_update
        @username = setting(:username) || 'admin1'
        @password = setting(:password) || 'panasonic'
    end

    def connected
    end

    def disconnected
    end

    COMMANDS = {
        power_on: :PON,
        power_off: :POF,
        power_query: :QPW,
        input: :IMS,
        volume: :AVL,
        audio_mute: :AMT
    }
    COMMANDS.merge!(COMMANDS.invert)

    #
    # Power commands
    #
    def power(state, opt = nil)
        self[:stable_state] = false
        if is_affirmative?(state)
            self[:power_target] = On
            do_send(:power_on, retries: 10, name: :power, delay_on_receive: 8000)
            logger.debug "requested to power on"
            do_send(:power_query)
        else
            self[:power_target] = Off
            do_send(:power_off, retries: 10, name: :power, delay_on_receive: 8000).then do
                schedule.in('10s') { do_send(:power_query) }
            end
            logger.debug "requested to power off"
        end
    end

    def power?(**options, &block)
        options[:emit] = block if block_given?
        do_send(:power_query, options)
    end

    #
    # Input selection
    #
    INPUTS = {
        hdmi: :HM1,
        hdmi2: :HM2,
        vga: :PC1,
        dvi: :DV1
    }
    INPUTS.merge!(INPUTS.invert)

    def switch_to(input)
        input = input.to_sym
        return unless INPUTS.has_key? input

        # Projector doesn't automatically unmute
        unmute if self[:mute]

        do_send(:input, INPUTS[input], retries: 10, delay_on_receive: 2000)
        logger.debug "requested to switch to: #{input}"

        self[:input] = input    # for a responsive UI
    end

    #
    # Mute Audio
    #
    def mute(val = true)
        actual = val ? 1 : 0
        logger.debug "requested to mute #{val}"
        do_send(:audio_mute, actual)    # Audio + Video
    end

    def unmute
        mute false
    end

    def muted?
        do_send(:audio_mute)
    end

    def volume(level)
        do_send(:volume, level)
    end

    def volume?
        do_send(:volume)
    end

    ERRORS = {
        ERR1: '1: Undefined control command',
        ERR2: '2: Out of parameter range',
        ERR3: '3: Busy state or no-acceptable period',
        ERR4: '4: Timeout or no-acceptable period',
        ERR5: '5: Wrong data length',
        ERRA: 'A: Password mismatch',
        ER401: '401: Command cannot be executed',
        ER402: '402: Invalid parameter is sent'
    }

    def received(data, resolve, command)        # Data is default received as a string
        logger.debug { "sent \"#{data}\" for #{command ? command[:data] : 'unknown'}" }

        # This is the ready response
        if data[0] == ' '
            @use_pass = data[1] == '1'
            if @use_pass
                @pass = "#{@username}:#{@password}:#{data[3..-1]}"
                @pass = Digest::MD5.hexdigest(@pass)
            end

            # Ignore this as it is not a response
            return :ignore
        else
            # Error Response
            if data[0] == 'E'
                error = data.to_sym
                self[:last_error] = ERRORS[error]

                # Check for busy or timeout
                if error == :ERR3 || error == :ERR4
                    logger.warn "Proj busy: #{self[:last_error]}"
                    return :retry
                else
                    logger.error "Proj error: #{self[:last_error]}"
                    return :abort
                end
            end

            data = data[2..-1]
            resp = data.split(':')
            cmd = COMMANDS[resp[0].to_sym]
            val = resp[1]

            case cmd
            when :power_on
                self[:power] = true
            when :power_off
                self[:power] = false
            when :power_query
                self[:power] = val.to_i == 1
            when :audio_mute
                self[:audio_mute] = val.to_i == 1
            when :volume
                self[:volume] = val.to_i
            when :input
                self[:input] = INPUTS[val.to_sym]
            end
        end

        :success
    end


    protected


    def do_send(command, param = nil, **options)
        if param.is_a? Hash
            options = param
            param = nil
        end

        # Default to the command name if name isn't set
        options[:name] = command unless options[:name]

        if param.nil?
            cmd = "00#{COMMANDS[command]}\r"
        else
            cmd = "00#{COMMANDS[command]}:#{param}\r"
        end

        send(cmd, options)
    end

    # Apply the password hash to the command if a password is required
    def apply_password(data)
        if @use_pass
            data = "#{@pass}#{data}"
        end

        return data
    end
end
