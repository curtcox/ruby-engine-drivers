# frozen_string_literal: true

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

        init_connection.then do
            query 'CORIOmax.Serial_Number',    expose_as: :serial_number
            query 'CORIOmax.Software_Version', expose_as: :firmware
        end
    end

    def disconnected
        schedule.clear
    end


    # ------------------------------
    # Main API

    def preset(id)
        set('Preset.Take', id).finally { sync_state }
    end
    alias switch_to preset

    def switch(signal_map)
        interactions = signal_map.flat_map do |slot, windows|
            Array(windows).map do |id|
                id = id.to_s[/\d+/].to_i unless id.is_a? Integer
                window id, 'Input', slot
            end
        end
        thread.finally(*interactions)
    end

    def window(id, property, value)
        set("Window#{id}.#{property}", value).then do
            self[:windows][:"window#{id}"][property.downcase.to_sym] = value
            signal_status :windows
        end
    end


    protected


    def init_connection
        username = setting :username
        password = setting :password

        exec('login', username, password, priority: 99).then { sync_state }
    end

    def do_poll
        logger.debug 'polling device'
        query 'Preset.Take', expose_as: :preset
    end

    # Get the presets available for recall - for some inexplicible reason this
    # has a wildly different API to the rest of the system state...
    def query_preset_list(expose_as: nil)
        exec('Preset.PresetList').then do |presets|
            presets.transform_keys { |key| key[/\d+/].to_i }
                   .transform_values do |val|
                       name, canvas, time = val.split ','
                       {
                           name:   name,
                           canvas: canvas,
                           time:   time
                       }
                   end

            self[expose_as] = presets unless expose_as.nil?

            presets
        end
    end

    def sync_state
        thread.finally(
            query('Preset.Take',   expose_as: :preset),
            query_preset_list(     expose_as: :presets),
            deep_query('Windows',  expose_as: :windows),
            deep_query('Canvases', expose_as: :canvases),
            deep_query('Layouts',  expose_as: :layouts)
        )
    end

    # ------------------------------
    # Base device comms

    def exec(command, *params, **opts)
        logger.debug { "executing #{command}" }

        defer = thread.defer

        opts[:on_receive] = lambda do |*args|
            received(*args) { |val| defer.resolve val }
        end

        send "#{command}(#{params.join ','})\r\n", opts

        defer.promise
    end

    def set(path, val, **opts)
        logger.debug { "setting #{path} to #{val}" }

        defer = thread.defer

        opts[:name] ||= path.to_sym
        send("#{path} = #{val}\r\n", opts).then do
            defer.resolve val
        end

        defer.promise
    end

    def query(path, expose_as: nil, **opts)
        logger.debug { "querying #{path}" }

        defer = thread.defer

        opts[:on_receive] = lambda do |*args|
            received(*args) do |val|
                self[expose_as.to_sym] = val unless expose_as.nil?
                defer.resolve val
            end
        end

        send "#{path}\r\n", opts

        defer.promise
    end

    def deep_query(path, expose_as: nil, **opts)
        logger.debug { "deep querying #{path}" }

        defer = thread.defer

        query(path, opts).then do |val|
            if val.is_a? Hash
                val.each_pair do |k, v|
                    val[k] = deep_query(k).value if v == '<...>'
                end
            end
            self[expose_as] = val unless expose_as.nil?
            defer.resolve val
        end

        defer.promise
    end

    def parse_response(lines, command)
        updates = lines.map { |line| line.chop.split ' = ' }
                       .to_h
                       .transform_values! do |val|
                           case val
                           when /^-?\d+$/    then Integer val
                           when 'NULL'       then nil
                           when /(Off)|(No)/ then false
                           when /(On)|(Yes)/ then true
                           else                   val
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
            if command[:data] =~ /^#{message}/i
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
