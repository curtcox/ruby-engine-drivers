# frozen_string_literal: true

load File.expand_path('./room_os.rb', File.dirname(__FILE__))

class Cisco::Spark::Sx20 < Cisco::Spark::RoomOs
    include ::Orchestrator::Security
    include ::Cisco::Spark::Xapi::Mapper

    descriptive_name 'Cisco Spark SX20'
    description <<~DESC
        Device access requires an API user to be created on the endpoint.
    DESC

    tokenize delimiter: Tokens::COMMAND_RESPONSE,
             wait_ready: Tokens::LOGIN_COMPLETE
    clear_queue_on_disconnect!

    # Restrict access to the direct API methods to admins
    protect_method :xcommand, :xconfigruation, :xstatus


    command 'Call Accept' => :accept,
            CallId_: Integer

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
            CallId_: Integer

    # configuration! 'Network/n/VLAN/Voice' => :set_voice_vlan,
    #                Mode: [:Auto, :Manual, :Off]
end
