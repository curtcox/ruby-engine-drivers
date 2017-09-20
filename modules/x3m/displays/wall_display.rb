# frozen_string_literal: true, encoding: ASCII-8BIT

module X3m; end
module X3m::Displays; end

class X3m::Displays::WallDisplay
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    tcp_port 4999  # control assumed via Global Cache
    descriptive_name '3M Wall Display'
    generic_name :Display

    description <<-DESC
        Display control is via RS-232 only. Ensure IP -> RS-232 converter has
        been configured to provide comms at 9600,N,8,1.
    DESC

    tokenize delimiter: "\r"

    def on_load
        on_update

        self[:power] = false

        # Meta data for inquiring interfaces
        self[:type] = :lcd
    end

    def on_unload
    end

    def on_update
        @id = setting(:monitor_id) || :all

        self[:volume_min] = setting(:volume_min) || 0
        self[:volume_max] = setting(:volume_max) || 100
    end

    def connected
        do_poll

        schedule.every '30s', method(:do_poll)
    end

    def disconnected
        schedule.clear
    end

    def do_poll

    end

    def power(state)
        set :power, is_affirmative?(state)
    end

    def volume(level)
        target = Util.scale level, 100, 30
        set :volume, target
    end

    def switch_to(input)
        set :input, input.to_sym
    end

    def mute_audio(state = true)

    end

    def unmute_audio

    end

    protected

    def set(command, param, opts = {}, &block)
        logger.debug { "Setting #{command} -> #{param}" }

        op_code, value = Protocol.lookup(command, param)

        packet = Protocol.build_packet(op_code, value, monitor_id: @id)

        opts[:emit] = block if block_given?
        opts[:name] ||= command

        send packet, opts
    end

    def received(data, resolve, command)
        logger.debug {
            byte_to_hex(data)
                .scan(/../)
                .map { |byte| "0x#{byte}" }
                .join ' '
        }

        begin
            response = Protocol.parse_response data
        rescue => parse_error
            logger.warn parse_error.message
            return :fail
        end

        :success
    end
end

module X3m::Displays::WallDisplay::Util
    module_function

    # Convert an integral value into a string with its hexadecimal
    # representation.
    #
    # as_hex(10, width: 2)
    #  => "0A"
    def as_hex_string(value, width:)
        value
            .to_s(16)
            .rjust(width, '0')
            .upcase
    end

    # Convert an integral value to a byte array, with each element containing
    # the ASCII character code that represents the original value at that
    # offset (big-endian).
    #
    # byte_arr(10, width: 2)
    #  => [48, 65]
    def byte_arr(value, length:)
        as_hex_string(value, width: length)
            .bytes
    end

    # Scale a value previous on a 0..old_max scale to it's equivalent within
    # 0..new_max
    def scale(value, old_max, new_max)
        (new_max * value) / old_max
    end

    # Expand a hashmap to provide inverted k/v pairs for bi-directional lookup
    def bidirectional(hash)
        hash
            .merge(hash.invert)
            .freeze
    end
end

module X3m::Displays::WallDisplay::Protocol
    module_function

    Util = ::X3m::Displays::WallDisplay::Util

    MARKER = {
        SOH: 0x01,
        STX: 0x02,
        ETX: 0x03,
        delimiter: 0x0d,
        reserved: 0x30
    }.freeze

    MONITOR_ID = Util.bidirectional({
        all: 0x2a
    }.merge(
        Hash[(1..9).zip(0x41..0x49)]
    ))

    MESSAGE_SENDER = Util.bidirectional({
        pc: 0x30
    })

    MESSAGE_TYPE = Util.bidirectional({
        set_parameter_command: 0x45,
        set_parameter_reply: 0x46
    })

    COMMAND = Util.bidirectional({
        brightness: 0x0110,
        contrast: 0x0112,
        volume: 0x0062,
        power: 0x0003,
        input: 0x02CB
    })

    # Definitions for non-numeric command arguments
    PARAMS = {
        power: {
            false => 0,
            true => 1
        },
        input: {
            vga: 0,
            dvi: 1,
            hdmi: 2,
            dp: 3
        }
    }
    PARAMS.transform_values! { |param| Util.bidirectional(param) }
    PARAMS.freeze

    # Map a symbolic command and parameter value to an [op_code, value] or an
    # op_code and value back to a [command, param]
    def lookup(command, param)
        op_code = COMMAND[command]
        value = PARAMS.dig command, param || param
        [op_code, value]
    end

    # Build a 'set_parameter_command' packet ready for transmission to the
    # device(s).
    def build_packet(op_code, value, monitor_id: :all)
        message = [
            MARKER[:STX],
            *Util.byte_arr(op_code, length: 4),
            *Util.byte_arr(value, length: 4),
            MARKER[:ETX]
        ]

        header = [
            MARKER[:SOH],
            MARKER[:reserved],
            MONITOR_ID[monitor_id],
            MESSAGE_SENDER[:pc],
            MESSAGE_TYPE[:set_parameter_command],
            *Util.byte_arr(message.length, length: 2)
        ]

        # XOR of byte 1 -> end of message payload for checksum
        bcc = (header.drop(1) + message).reduce(:^)

        header + message << bcc << MARKER[:delimiter]
    end

    # Parse a response packet out to a nice readable structure.
    def parse_response(packet)
        capture = ->(name, len = 1) { "(?<#{name}>.{#{len}})" }

        structure = %r{
            #{MARKER[:SOH]}
            #{MARKER[:reserved]}
            #{capture['receiver']}
            #{capture['monitor_id']}
            #{capture['message_type']}
            #{capture['message_len', 2]}
            #{MARKER[:STX]}
            #{capture['result_code', 2]}
            #{capture['op_code', 4]}
            #{capture['message_type', 2]}
            #{capture['max_value', 4]}
            #{capture['value', 4]}
            #{MARKER[:ETX]}
            #{capture['bcc']}
            #{MARKER[:delimiter]}
        }x

        rx = packet.match structure
        if rx.nil?
            raise 'invalid packet structure'
        end

        bcc = packet.bytes[1..-3].reduce(:^)
        if bcc != rx[:bcc]
            raise 'invalid checksum'
        end

        decode = ->(capture_name) { rx[capture_name].hex }

        resolve = lambda do |hash, capture_name|
            raw_value = rx[capture_name]
            value = raw_value.length > 1 ? raw_value.hex : raw_value.ord
            hash[value] || value
        end

        command, param = lookup decode[:opcode], decode[:value]

        {
            receiver: resolve[MESSAGE_SENDER, :receiver],
            monitor_id: resolve[MONITOR_ID, :monitor_id],
            message_type: resolve[MESSAGE_TYPE, :message_type],
            success: decode[:result_code] == 0,
            command: command,
            value: param
        }
    end
end
