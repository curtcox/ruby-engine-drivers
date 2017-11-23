# frozen_string_literal: true

require 'json'
require 'securerandom'

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

        # Async events only

        :success
    end

    # Execute an xCommand on the device.
    #
    # @param command [String] the command to execute
    # @param args [Hash] the command arguments
    def xcommand(command, args = {})
        send_xcommand command, args
    end

    protected

    # Perform the actual command execution - this allows device implementations
    # to protect access to #xcommand and still refer the gruntwork here.
    def send_xcommand(command, args = {})
        request = Xapi::Action.xcommand command, args

        do_send request, name: command do |response|
            # The result keys are a little odd - they're a concatenation of the
            # last two command elements and 'Result'.
            # For example:
            #   `xCommand Video Input SetMainVideoSource...`
            # becomes:
            #   `InputSetMainVideoSourceResult`
            result_key = command.split(' ').last(2).join('') + 'Result'
            result = response.dig 'CommandResponse', result_key

            if result
                if result['status'] == 'OK'
                    :success
                else
                    reason = result.dig 'Reason', 'Value'
                    logger.error reason if reason
                    :abort
                end
            else
                logger.warn 'Unexpected response format'
                :abort
            end
        end
    end

    # Execute raw command on the device.
    #
    # Automatically appends a result tag and handles routing of response
    # handling for async interactions. If a block is passed a pre-parsed
    # response object will be yielded to it.
    #
    # @param command [String] the raw command to execute
    # @yield [response] a pre-parsed response object for the command
    def do_send(command, **options)
        request_id = generate_request_uuid

        send "#{command} | resultId=\"#{request_id}\"\n", **options do |rx|
            begin
                response = JSON.parse rx, object_class: CaseInsensitiveHash

                if response['ResultId'] == request_id
                    if block_given?
                        yield response
                    else
                        :success
                    end
                else
                    :ignore
                end
            rescue JSON::ParserError => error
                logger.warn "Malformed device response: #{error}"
                :fail
            end
        end
    end

    def generate_request_uuid
        SecureRandom.uuid
    end
end

class CaseInsensitiveHash < ActiveSupport::HashWithIndifferentAccess
    def [](key)
        super convert_key(key)
    end

    protected

    def convert_key(key)
        key.respond_to?(:downcase) ? key.downcase : key
    end
end
