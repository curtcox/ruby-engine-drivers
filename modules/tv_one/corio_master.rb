module TvOne; end

# Documentation: https://aca.im/driver_docs/TV+One/CORIOmaster-Commands-v1.7.0.pdf

class TvOne::CorioMaster
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder


    tcp_port 10001
    descriptive_name 'tvOne CORIOmaster image processor'
    generic_name :VideoWall

    tokenize wait_ready: 'Interface Ready', callback: :tokenize

    default_settings username: 'admin', password: 'adminpw'


    # ------------------------------
    # Calllbacks

    def connected
        schedule.every('60s') do
            do_poll
        end

        username = setting :username
        password = setting :password
        exec('login', username, password, priority: 99).then do
            query 'CORIOmax.Serial_Number', expose_as: :serial_number
            query 'CORIOmax.Software_Version', expose_as: :firmware
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

    def query(path, expose_as: nil, **opts, &callback)
        logger.debug { "querying #{path}" }

        if expose_as || callback
            opts[:on_receive] = lambda do |*args|
                received(*args) do |val|
                    self[expose_as] = val unless expose_as.nil?
                    callback&.call val
                end
            end
        end

        send "#{path}\r\n", opts
    end

    def parse_response(lines, command)
        updates = lines.map { |line| line.chop.split ' = ' }
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

        if updates.size == 1 && updates.include?(command)
            # Single property query
            updates.values.first
        elsif updates.values.all?(&:nil?)
            # Property list
            updates.keys
        else
            # Property set
            updates.reject { |k, _| k.end_with? '()' }
                   .transform_keys! do |x|
                       x.sub(/^#{command}\.?/, '').downcase!.to_sym
                   end
        end
    end

    def tokenize(buffer)
        result_line_start = buffer.index(/^!/)

        return false unless result_line_start

        result_line_end = buffer.index("\r\n", result_line_start)

        if result_line_end
            result_line_end + 2
        else
            false
        end
    end

    def received(data, resolve, command)
        logger.debug { "received: #{data}" }

        *body, result = data.lines
        type, message = /^!(\w+)\W*(.*)\r\n$/.match(result).captures

        case type
        when 'Done'
            if command[:data].start_with? message
                yield parse_response body, message if block_given?
                :success
            else
                :ignore
            end
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
