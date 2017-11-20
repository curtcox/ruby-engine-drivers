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

    tokenize delimiter: "\n}\n",
             wait_ready: "OK\n" # *r Login successful\n\nOK\n
    clear_queue_on_disconnect!

    def on_load; end

    def on_unload; end

    def on_update; end

    def connected
        do_send 'Echo off', wait: false, priority: 96
        do_send 'xPreferences OutputMode JSON', wait: false
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
        do_send Xapi::Action.xcommand(command, args)
    end

    protected

    # Execute and arbitary command on the device.
    #
    # @param command [String] the command to execute
    # @param options [Hash] send options to be passed to the transport layer
    def do_send(command, **options)
        logger.debug { "-> #{command}" }
        send "#{command}\n", **options
    end
end
