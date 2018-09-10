module DigitalProjection; end

# Documentation: http://www.digitalprojection.co.uk/dpdownloads/Protocol/Simplified-Protocol-Guide-Rev-H.pdf

class DigitalProjection::Evision7500
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    tcp_port 7000
    descriptive_name 'Digital Projection E-Vision Laser 7500'
    generic_name :Display

    tokenize indicator: /ack|ACK/, delimiter: "\x0D"

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
        :hdmi => 0,
        :hdmi2 => 1,
        :vga => 2,
        :comp => 3,
        :dvi => 4,
        :displayport => 5,
        :hdbaset => 6,
        :sdi3g => 7
    }
    INPUTS.merge!(INPUTS.invert)
    def switch_to(input)
        input = input.to_sym if input.class == String
        send_cmd("input = #{INPUTS[input]}", name: :input)
    end

    def input?
        send_cmd("power ?", name: :input, priority: 0)
    end

    def send_cmd(cmd, options = {})
        req = "*#{cmd}"
        req << 0x0D
        logger.debug { "tell -- 0x#{byte_to_hex(req)} -- #{options[:name]}" }
        send(req, options)
    end

    def received(data, deferrable, command)
        logger.debug { "Received 0x#{byte_to_hex(data)}" }

        return :success if command.nil? || command[:name].nil?

        # \A is the beginning of the line
        if(data =~ /\ANAK|\Anack/) # syntax error or other
            logger.debug { data }
            return :failed
        end

        # regex match the value
        data = data[-1].to_i
        case command[:name]
        when :power
            self[:power] = data == 1
        when :input
            self[:input] = INPUT[data]
        end
        return :success
    end


end
