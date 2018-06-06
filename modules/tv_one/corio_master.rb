module TvOne; end

# Documentation: https://aca.im/driver_docs/TV+One/CORIOmaster-Commands-v1.7.0.pdf

class TvOne::CorioMaster
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder


    tcp_port 10001
    descriptive_name 'tvOne CORIOmaster image processor'
    generic_name :VideoWall

    tokenize delimiter: /(?<=^!(Info)|(Done)|(Error)|(Event)).*\r\n/,
             wait_ready: 'Interface Ready'

    default_settings username: 'admin', password: 'adminpw'


    # ------------------------------
    # Calllbacks

    def on_load
        on_update
    end

    def on_update
        @username = setting :username
        @password = setting :password
    end

    def connected
        schedule.every('60s') do
            do_poll
        end

        exec('login', @username, @password, priority: 99).then do
            query 'CORIOmax.Serial_Number', expose_as: :serial_number
            query 'CORIOmax.Software_Version', expose_as: :version
        end
    end

    def disconnected
        schedule.clear
    end


    # ------------------------------
    # Main API

    def preset(id)
        set('Preset.Take', id).then { self[:preset] = id }
    end
    alias switch_to preset

    def window(id, property, value)
        set "Window#{id}.#{property}", value
    end


    protected


    def do_poll
        logger.debug 'polling device state'

        query 'Preset.Take', expose_as: :preset
    end

    # ------------------------------
    # Base device comms

    def exec(command, *params, **opts)
        logger.debug { "executing #{command}" }
        send "#{command}(#{params.join ','})\r\n", opts
    end

    def set(path, val, **opts)
        logger.debug { "setting #{path} to #{val}" }
        opts[:name] ||= path.to_sym
        send "#{path} = #{val}\r\n", opts
    end

    def query(path, expose_as: nil, **opts, &blk)
        logger.debug { "querying #{path}" }
        blk = ->(val) { self[expose_as] = val } unless expose_as.nil?
        opts[:emit] ||= ->(d, r, c) { received d, r, c, &blk } unless blk.nil?
        send "#{path}\r\n", opts
    end

    def parse_response(lines)
        updates = lines.map { |line| line.split ' = ' }
                       .to_h
                       .transform_values! do |val|
                           case val
                           when /^\d+$/ then Integer val
                           when 'NULL'  then nil
                           when 'Off'   then false
                           when 'On'    then true
                           else              val
                           end
                       end

        if updates.size == 1 && updates.include?(message)
            # Single property query
            updates.first.value
        elsif updates.values.all?(&:nil?)
            # Property list
            updates.keys
        else
            # Property set
            updates.reject { |k, _| k.end_with '()' }
                   .transform_keys! do |x|
                       x.sub(/^#{message}\.?/, '').downcase!.to_sym
                   end
        end
    end

    def received(data, resolve, command)
        logger.debug { "received: #{data}" }

        *body, result = data.lines
        type, message = /^!(\w+)\W*(.*)$/.match(result).captures

        case type
        when 'Done'
            yield parse_response body if block_given?
            :success
        when 'Info'
            logger.info message
            :success
        when 'Error'
            logger.error message
            :fail
        when 'Event'
            logger.warn { "unhandled event: #{message}" }
            :ignore
        else
            logger.error { "unhandled response: #{data}" }
            :abort
        end
    end
end
