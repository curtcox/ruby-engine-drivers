module Sony; end
module Sony::Display; end

# Documentation: 

class Sony::Display::CBX
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder


    # Discovery Information
    tcp_port 10000
    descriptive_name 'Sony CBX RS-232 Passthru Module'
    generic_name :Display

    # Communication settings
    tokenize indicator: "\x02\x10", callback: :check_complete


    def on_load
        self[:power] = false
        self[:type] = :lcd
    end

    def on_update
    end

    def connected
        schedule.every('60s') { do_poll }
    end

    def disconnected
        schedule.clear
    end

    # power device
    def power(state)
		state = is_affirmative?(state)
		self[:power_target] = state
		power? do
			if state && !self[:power]		# Request to power on if off
				self[:stable_state] = false
				do_send([COMMANDS[:power]], :timeout => 15000, :delay_on_receive => 5000, :name => :power)
				
			elsif !state && self[:power]	# Request to power off if on
				self[:stable_state] = false
				do_send([COMMANDS[:power]], :timeout => 15000, :delay_on_receive => 5000, :name => :power)
				self[:frozen] = false
			end
		end
	end
	
	def power?(options = {}, &block)
		options[:emit] = block
		do_send(STATUS_CODE[:system_status], options)
	end

    protected

        # category, command
        COMMANDS = {
            power_on: [0x00, 0x02, 0x01, 0x8F],
            power_off: [0x00, 0x02, 0x00, 0x8E],
            input1: [0x02, 0x03, 0x04, 0x01, 0x96],
            picture_mute: [0x0D, 0x03, 0x01, 0x00, 0x9D],
            picture_unmute: [0x0D, 0x03, 0x01, 0x01 0x9E],
            audio_mute: [0x06, 0x03, 0x01, 0x01, 0x97],
            audio_unmute: [0x06, 0x03, 0x01, 0x00, 0x96]
            }
        COMMANDS.merge!(COMMANDS.invert)

    def do_poll(*args)
        power?({:priority => 0}) do
            if self[:power]
                input1?
                picture_mute?
                audio_mute?
                do_send(:signal_status, {:priority => 0})
            end
        end
    end

    def build_checksum(command)
        check = 0
        command.each do |byte|
            check = (check + byte) & 0xFF
        end
        [check]
    end

    def do_send(command, param = nil, options = {})
        # Check for missing params
        if param.is_a? Hash
            options = param
            param = nil
        end

        # Control + Mode
        if param.nil?
            options[:name] = command
            cmd = [0x8C, 0x00] + COMMANDS[command] + [0xFF, 0xFF]
        else
            options[:name] = :"#{command}_cmd"
            type = [0x8C, 0x00] + COMMANDS[command]
            if !param.is_a?(Array)
                param = [param]
            end
            data = [param.length + 1] + param
            cmd = type + data
        end

        cmd = cmd + build_checksum(cmd)

        send(cmd, options)
    end
end
