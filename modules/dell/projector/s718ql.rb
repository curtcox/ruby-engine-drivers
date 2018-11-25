require 'protocols/simple_snmp'

module Dell; end
module Dell::Projector; end

# Documentation: https://aca.im/driver_docs/Dell/dell-s718ql-snmp.pdf

class Dell::Projector::S718ql
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    udp_port 161
    descriptive_name 'Dell S718QL Projector'
    generic_name :Display

    default_settings({
        snmp_timeout: 4000,
        snmp_options: {
            version: 'v2c',
            community: 'private',
        }
    })

    def on_load
        self[:volume_min] = 0
        self[:volume_max] = 100

        # Meta data for inquiring interfaces
        self[:type] = :projector

        schedule.every('60s') { do_poll }
        on_update
    end

    def on_unload
        @client.close
    end

    def on_update
        #new_client if @resolved_ip
        options = setting(:snmp_options) || {}
        proxy = Protocols::SimpleSnmp.new(self)
        options[:proxy] = proxy
        @client = NETSNMP::Client.new(options.to_h.symbolize_keys)
    end

    #def on_unload
    #    @transport&.close
    #    @transport = nil
    #    @client&.close
    #    @client = nil
    #end

    def hostname_resolution(ip)
        @resolved_ip = ip

        # Create a new client once we know the IP address of the device.
        # Might have been a hostname in the settings.
        #new_client
    end

    def new_client
        return
        @transport&.close
        @client&.close

        @transport = Protocols::Snmp.new(self, setting(:snmp_timeout))
        @transport.register(@resolved_ip, remote_port)
        config = setting(:snmp_options).to_h.symbolize_keys.merge({proxy: @transport})
        @client = NETSNMP::Client.new(config)
    end

    #
    # Power commands
    def power(state, opt = nil)
        if is_affirmative?(state)
            logger.debug "-- requested to power on"
            resp = @client.set(oid: '1.3.6.1.4.1.2699.2.4.1.4.3.0', value: 11)
            self[:power] = On
        else
            logger.debug "-- requested to power off"
            @client.set(oid: '1.3.6.1.4.1.2699.2.4.1.4.3.0', value: 7)
            self[:power] = Off
        end
    end

    def power?
        state = @client.get(oid: '1.3.6.1.4.1.2699.2.4.1.4.2.0')
        logger.debug { "Power State #{state.inspect}" }
	self[:power] = state == 11 || state == 10
        self[:warming] = state == 10
        self[:cooling] = state == 9
        state
    end

    #
    # Input selection
    INPUTS = {
        :hdmi => 5,
        :hdmi2 => 14,
        :hdmi3 => 17,
	:network => 16
    }
    INPUTS.merge!(INPUTS.invert)

    def switch_to(input)
        input = input.to_sym
        value = INPUTS[input]
        raise "unknown input '#{value}'" unless value

        logger.debug "Requested to switch to: #{input}"
        response = @client.set(oid: '1.3.6.1.4.1.2699.2.4.1.6.1.1.3.1', value: value)
        logger.debug "Recieved: #{response}"
        self[:input] = input    # for a responsive UI
        self[:mute] = false
    end

    def input?
        input = @client.get(oid: '1.3.6.1.4.1.2699.2.4.1.6.1.1.3.1')
        self[:input] = INPUTS[input]
    end

    #
    # Volume commands are sent using the inpt command
    def volume(vol, options = {})
        vol = vol.to_i
        vol = 0 if vol < 0
        vol = 100 if vol > 100

        @client.set(oid: '1.3.6.1.4.1.2699.2.4.1.16.2.0', value: vol)

        # Seems to only return ':' for this command
        self[:volume] = vol
    end

    def volume?
        self[:volume] = @client.get(oid: '1.3.6.1.4.1.2699.2.4.1.16.2.0')
    end

    #
    # Mute Audio and Video
    def mute(state = true)
        state = is_affirmative?(state)
        logger.debug { "-- requested to mute video #{state}" }
        @client.set(oid: '1.3.6.1.4.1.2699.2.4.1.6.2.0', value: (state ? 1 : 2))
        self[:mute] = state
    end

    def unmute
        mute false
    end

    def mute?
        self[:mute] = @client.get(oid: '1.3.6.1.4.1.2699.2.4.1.6.2.0') == 1
    end

    # Audio mute
    def mute_audio(state = true)
        state = is_affirmative?(state)
        logger.debug { "-- requested to mute audio #{state}" }
        @client.set(oid: '1.3.6.1.4.1.2699.2.4.1.16.3.0', value: (state ? 1 : 2))
        self[:audio_mute] = state
    end

    def unmute_audio
        mute_audio(false)
    end

    def audio_mute?
        self[:audio_mute] = @client.get(oid: '1.3.6.1.4.1.2699.2.4.1.16.3.0') == 1
    end

    def query_error
        self[:last_error] = @client.get(oid: '1.3.6.1.4.1.2699.2.4.1.18.1.1.5.1')
    end

    def do_poll
	power?
	input?
	mute?
    end

    protected

    def received(data, resolve, command)
        # return the data which resolves the request promise.
        # the proxy uses fibers to provide this to the NETSNMP client
        data
    end
end
