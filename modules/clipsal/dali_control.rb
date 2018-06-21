module Clipsal; end

# Protocol: https://aca.im/driver_docs/Clipsal/DALIcontrol-Application-Note-3rd-Party-Interface-Rev1-3.pdf

class Clipsal::DaliControl
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    udp_port 1235   # Can also use TCP/1001, UDP recommended by protocol doc
    descriptive_name 'Clipsal DALI line controller'
    generic_name :Lighting
    description 'Ethernet to DALI bus gateway.'

    delay between_sends: 50
    wait_response false

    def on_load
        # All protocol information is one way only
        set_connected_state true
    end

    def on_unload
    end

    def on_update
    end

    def connected
    end

    def disconnected
    end

    [
        :off,
        :up,
        :down,
        :step_up,
        :step_down,
        :max,
        :min
    ].each do |action|
        define_method action do |controller, line, address|
            dali_group_action controller, line, address, action
        end
    end

    def recall_scene(controller, line, address, scene)
        scene -= 1 # Allow for 1 based scene indexes from humans
        dali_group_action controller, line, address, :"scene_#{scene}"
    end

    def received(data, deferrable, command)
        # Should never occur - gateway is TX only
        logger.debug { "Received: #{data}" }
    end

    protected

    def dali_group_action(controller, line, address, action)
        logger.debug do
            "Controller #{controller} [#{line}:#{address}] #{action}"
        end

        send Protocol.build_group_packet controller, line, address,
                                         :dali_action, action
    end

end

module Clipsal::DaliControl::Protocol
    module_function

    MARKER = {
        indicator: '$',
        delimiter: '*'
    }.freeze

    COMMAND_TYPE = {
        dali: 14,
        group: 15
    }.freeze

    LINE = {
        both: 0,
        line_a: 1,
        line_b: 2
    }.freeze

    ADDRESS_TYPE = {
        broadcast: 0,
        group: 1,
        ballast: 2
    }.freeze

    DALI_ACTION_TYPE = {
        dali_action: 0,
        arc_level: 1
    }.freeze

    GROUP_ACTION_TYPE = {
        dali_action: 80,
        arc_level: 81,
        sequence: 82,
        list: 85
    }.freeze

    DALI_ACTION = {
        off: 0,
        up: 1,
        down: 2,
        step_up: 3,
        step_down: 4,
        max: 5,
        min: 6
    }.merge(
        Hash[(:scene_0..:scene_15).zip(0x10..0x1f)]
    ).freeze

    def build_dali_packet(controller, line, address, address_type, action_type, action)
        action = case action_type
                 when :dali_action
                     DALI_ACTION[action]
                 else
                     action
                 end

        payload = [
            format('%02i', LINE[line]),
            format('%03i', address),
            format('%01i', ADDRESS_TYPE[address_type]),
            format('%01i', DALI_ACTION_TYPE[action_type]),
            format('%03i', action)
        ]

        build_packet controller, :dali, *payload
    end

    def build_group_packet(controller, line, address, action_type, action)
        address += 64 if line == :line_b

        action = case action_type
                 when :dali_action
                     DALI_ACTION[action]
                 else
                     action
                 end

        payload = [
            format('%03i', address),
            format('%02i', GROUP_ACTION_TYPE[action_type]),
            format('%02X', action)
        ]

        build_packet controller, :group, *payload
    end

    def build_packet(controller, command_type, *payload)
        [
            MARKER[:indicator],
            format('%03i', controller),
            format('%03i', COMMAND_TYPE[command_type]),
            format('%03i', payload.map(&:length).reduce(:+)),
            *payload,
            MARKER[:delimiter]
        ].join ''
    end
end
