module Aca; end

class Aca::DeviceProbe
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security

    descriptive_name 'ACA Device Probe'
    generic_name :Probe
    implements :device
    description 'Passthrough / comms logger for probing device protocols'

    default_settings hex: false

    # Restrict sending on arbitrary commands to admin / tech support only
    protect_method :send_data

    def on_load
        # Log instantiation events so we have an audit trail if this is ever
        # added to a prod system.
        logger.warn "Device probe loaded for #{remote_address}:#{remote_port}"

        on_update
    end

    def on_unload
        logger.warn "Device probe removed for #{remote_address}:#{remote_port}"
    end

    def on_update; end

    def connected
        logger.debug 'Connected'
    end

    def disconnected
        logger.debug 'Disconnected'
    end

    def send_data(data, opts = {}, &block)
        log_tx data, current_user

        opts[:emit] = block if block_given?
        opts[:hex_string] = true if transcode?
        opts[:wait] ||= false

        send data, opts
    end

    protected

    def received(data, resolve, command)
        log_rx data
        :success
    end

    def log_tx(data, user)
        logger.warn { "-> \"#{humanify data}\" (#{user.name} <#{user.email}>)" }
    end

    def log_rx(data)
        logger.info { "<- \"#{humanify data}\"" }
    end

    def transcode?
        is_affirmative? setting(:hex)
    end

    def humanify(data)
        if transcode?
            as_hex data
        else
            data
        end
    end

    # Map raw binary data returned from a device, into a nice human readable
    # string with the data represented as cleanly spaced hex bytes.
    def as_hex(data)
        byte_to_hex(data)
            .scan(/../)
            .map { |byte| "0x#{byte}" }
            .join ' '
    end
end
