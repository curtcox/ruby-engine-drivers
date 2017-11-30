# frozen_string_literal: true

load File.expand_path('./room_os.rb', File.dirname(__FILE__))

class Cisco::Spark::Sx20 < Cisco::Spark::RoomOs
    include ::Orchestrator::Security
    include ::Cisco::Spark::Xapi::Mapper

    descriptive_name 'Cisco Spark SX20'
    description <<~DESC
        Device access requires an API user to be created on the endpoint.
    DESC

    tokenize delimiter: Xapi::Tokens::COMMAND_RESPONSE,
             wait_ready: Xapi::Tokens::LOGIN_COMPLETE
    clear_queue_on_disconnect!

    # Restrict access to the direct API methods to admins
    protect_method :xcommand, :xstatus, :xfeedback


    command 'Call Accept' => :accept,
            _CallId: Integer

    CAMERA_MOVE_DIRECTION = [
        :Left,
        :Right,
        :Up,
        :Down,
        :ZoomIn,
        :ZoomOut
    ].freeze
    command 'Call FarEndCameraControl Move' => :far_end_camera,
            Value: CAMERA_MOVE_DIRECTION,
            _CallId: Integer

    # configuration! 'Network/n/VLAN/Voice' => :set_voice_vlan,
    #                Mode: [:Auto, :Manual, :Off]
end
