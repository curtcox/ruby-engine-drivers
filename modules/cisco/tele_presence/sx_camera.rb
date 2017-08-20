load File.expand_path('./sx_telnet.rb', File.dirname(__FILE__))
load File.expand_path('./sx_camera_common.rb', File.dirname(__FILE__))


class Cisco::TelePresence::SxCamera < Cisco::TelePresence::SxTelnet
    include Cisco::TelePresence::SxCameraCommon

    # Communication settings
    tokenize delimiter: "\r",
             wait_ready: "login:"
    clear_queue_on_disconnect!

    descriptive_name 'Cisco TelePresence Camera'
    generic_name :Camera
end
