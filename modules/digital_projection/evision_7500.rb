module DigitalProjection; end

# Documentation: http://www.digitalprojection.co.uk/dpdownloads/Protocol/Simplified-Protocol-Guide-Rev-H.pdf

class DigitalProjection::Evision7500
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 7000
    descriptive_name 'Digital Projection E-Vision Laser 4K'
    generic_name :Display

    tokenize delimiter: "\x0D"

    def on_load
        on_update
    end

    def on_update
    end

    def connected
        do_poll
        schedule.every('60s') do
            logger.debug "-- Polling Display"
            do_poll
        end
    end

    def disconnected
        schedule.clear
    end

    def do_poll
        power? do
            if self[:power]
                input?
            end
        end
    end

    def power(state)
        target = is_affirmative?(state)
        self[:power_target] = target

        logger.debug { "Target = #{target} and self[:power] = #{self[:power]}" }
        if target == On && self[:power] != On
            send_cmd("power = 1", name: :power, delay: 2000, timeout: 10000)
        elsif target == Off && self[:power] != Off
            send_cmd("power = 0", name: :power, timeout: 10000)
        end
    end

    def power?
        send_cmd("power ?", name: :power, priority: 0)
    end

    INPUTS = {
        :display_port => 0,
        :hdmi => 1,
        :hdmi2 => 2,
        :hdbaset => 3,
        :sdi3g => 4,
        :hdmi3 => 5,
        :hdmi4 => 6
    }
    INPUTS.merge!(INPUTS.invert)
    def switch_to(input)
        input = input.to_sym if input.class == String
        send_cmd("input = #{INPUTS[input]}", name: :input)
    end

    def input?
        send_cmd("input ?", name: :input, priority: 0)
    end

    # this projector uses a laser instead of a lamp
    def laser?
        send_cmd("laser.hours ?", name: :laser_inq, priority: 0)
    end

    def laser_reset
        send_cmd("laser.reset", name: :laser_reset)
    end

    def error?
        send_cmd("errcode", name: :error, priority: 0)
    end

    def freeze(state)
        target = is_affirmative?(state)
        self[:power_target] = target

        logger.debug { "Target = #{target} and self[:freeze] = #{self[:freeze]}" }
        if target == On && self[:freeze] != On
            send_cmd("freeze = 1", name: :freeze)
        elsif target == Off && self[:freeze] != Off
            send_cmd("freeze = 0", name: :freeze)
        end
    end

    def freeze?
        send_cmd("freeze ?", name: :freeze, priority: 0)
    end

    def send_cmd(cmd, options = {})
        req = "*#{cmd}"
        logger.debug { "Sending: #{req}" }
        req << 0x0D
        send(req, options)
    end

    def received(data, deferrable, command)
        logger.debug { "Received: #{data}" }

        return :success if command.nil? || command[:name].nil?

        # \A is the beginning of the line
        if(data =~ /\ANAK|\Anack/) # syntax error or other
            return :failed
        end

        case command[:name]
        when :power
            self[:power] = data[-1] == "1"
        when :input
            self[:input] = INPUT[data[-1].to_i]
        when :laser_inq
            # return whatever number is at the end of the string
            self[:laser] = data[/\d+\z/].to_i
        when :error
        when :freeze
            self[:freeze] = data[-1] == "1"
        end
        return :success
    end


end
