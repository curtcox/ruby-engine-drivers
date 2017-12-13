# frozen_string_literal: true

load File.join(__dir__, 'room_os.rb')

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

    protect_method :xcommand, :xconfigruation, :xstatus

    command 'Audio Microphones Mute' => :mic_mute_on
    command 'Audio Microphones Unmute' => :mic_mute_off
    command 'Audio Microphones ToggleMute' => :mic_mute_toggle
    state '/Status/Audio/Microphones/Mute' => :mic_mute

    command 'Audio Sound Play' => :play_sound,
            Sound: [:Alert, :Bump, :Busy, :CallDisconnect, :CallInitiate,
                    :CallWaiting, :Dial, :KeyInput, :KeyInputDelete, :KeyTone,
                    :Nav, :NavBack, :Notification, :OK, :PresentationConnect,
                    :Ringing, :SignIn, :SpecialInfo, :TelephoneCall,
                    :VideoCall, :VolumeAdjust, :WakeUp],
            Loop_: [:Off, :On]
    command 'Audio Sound Stop' => :stop_sound

    command 'Standby Deactivate' => :wake_up
    command 'Standby Activate' => :standby
    command 'Standby ResetTimer' => :reset_standby_timer, Delay: (1..480)
    state '/Status/Standby/State' => :standby

    command! 'SystemUnit Boot' => :reboot, Action_: [:Restart, :Shutdown]
end
