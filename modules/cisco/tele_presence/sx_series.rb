load File.expand_path('./sx_telnet.rb',        File.dirname(__FILE__))
load File.expand_path('./sx_series_common.rb', File.dirname(__FILE__))


class Cisco::TelePresence::SxSeries < Cisco::TelePresence::SxTelnet
    include Cisco::TelePresence::SxSeriesCommon

    # Communication settings
    tokenize delimiter: "\r",
             wait_ready: "login:"
    clear_queue_on_disconnect!

    # Discovery Information
    descriptive_name 'Cisco TelePresence'
    generic_name :VidConf
end
