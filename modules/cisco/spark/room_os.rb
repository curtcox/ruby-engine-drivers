# frozen_string_literal: true

Dir[File.join(File.dirname(__FILE__), 'xapi', '*.rb')].each { |f| load f }

module Cisco; end
module Cisco::Spark; end

class Cisco::Spark::RoomOs
    include ::Orchestrator::Constants

    Xapi = Cisco::Spark::Xapi

    implements :ssh
    descriptive_name 'Cisco Spark Room Device'
    generic_name :VidConf

    description <<~DESC
        Low level driver for any Cisco Spark Room OS device. This may be used
        if direct access is required to the device API, or a required feature
        is not provided by the device specific implementation.

        Where possible use the implementation for room device in use
        (i.e. SX80, Spark Room Kit etc).
    DESC

    tokenize delimiter: /(?<=\n})|(?<=\n{})\n/,
             wait_ready: "*r Login successful\n\nOK\n\n"
    clear_queue_on_disconnect!

    def on_load; end

    def on_unload; end

    def on_update; end

    def connected
        send "Echo off\n", wait: false, priority: 96
        send "xPreferences OutputMode JSON\n", wait: false
    end

    def disconnected; end

    def received(data, deferrable, command)
        logger.debug { "<- #{data}" }
    end

    # Execute an xCommand on the device.
    #
    # @param command [String] the command to execute
    # @param args [Hash] the command arguments
    def xcommand(command, args = {})
        request = Xapi::Action.xcommand command, args

        send request, name: command
    end
end
