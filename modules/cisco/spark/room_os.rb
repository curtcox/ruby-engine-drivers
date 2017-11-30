# frozen_string_literal: true

require 'json'
require 'securerandom'

module Cisco; end
module Cisco::Spark; end

module Cisco::Spark::Xapi; end
module Cisco::Spark::Util; end
Dir[File.join(__dir__, '{xapi,util}', '*.rb')].each { |lib| load lib }

class Cisco::Spark::RoomOs
    include ::Orchestrator::Constants

    Xapi = ::Cisco::Spark::Xapi
    Util = ::Cisco::Spark::Util

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

    tokenize \
        delimiter: Regexp.union([ # Zero-width groups (included in response)
            '}',
            '{}',
            'Command not recognized.',
            'OK'
        ].map { |delim| /(?<=^#{delim})[\r\n]+/ }),
        wait_ready: /\*r Login successful[\r\n]+/

    clear_queue_on_disconnect!

    def on_load
        on_update
    end

    def on_unload; end

    def on_update
        self[:peripheral_id] = setting(:peripheral_id) || "aca-#{edge_id}"
        self[:version] = setting(:version) || "#{self.class.name}-#{version}"

        # Force a reconnect and event resubscribe following module updates.
        disconnect if self[:connected]
    end

    def connected
        send "Echo off\n", priority: 96 do |response|
            :success if response.starts_with? "\e[?1034h"
        end

        send "xPreferences OutputMode JSON\n", wait: false

        register_control_system.then do
            schedule.every('30s') { heartbeat timeout: 35 }
        end

        subscribe_to_configuration
    end

    def disconnected
        clear_subscriptions

        schedule.clear
    end

    # Handle all incoming data from the device.
    #
    # In addition to acting an the normal Orchestrator callback, on_receive
    # procs also pipe through here for initial JSON decoding. See #do_send.
    def received(data, deferrable, command)
        logger.debug { "<- #{data}" }

        response = JSON.parse data, object_class: Util::CaseInsensitiveHash

        if block_given?
            # Let any pending command response handlers have first pass...
            yield(response).tap do |command_result|
                # Otherwise support interleaved async events
                unhandled = [:ignore, nil].include? command_result
                subscriptions.notify response if unhandled
            end
        else
            subscriptions.notify response
            :ignore
        end
    rescue JSON::ParserError => error
        case data.strip
        when 'OK'
            :success
        when 'Command not recognized.'
            logger.error { "Command not recognized: `#{command[:data]}`" }
            :abort
        else
            logger.warn { "Malformed device response: #{error}" }
            :fail
        end
    end

    # Execute an xCommand on the device.
    #
    # @param command [String] the command to execute
    # @param args [Hash] the command arguments
    # @return [::Libuv::Q::Promise] resolves when the command completes
    def xcommand(command, args = {})
        send_xcommand command, args
    end

    # Push a configuration settings to the device.
    #
    # @param path [String] the configuration path
    # @param settings [Hash] the configuration values to apply
    # @param [::Libuv::Q::Promise] resolves when the commands complete
    def xconfiguration(path, settings)
        send_xconfigurations path, settings
    end

    # Trigger a status update for the specified path.
    #
    # @param path [String] the status path
    # @param [::Libuv::Q::Promise] resolves with the status response as a Hash
    def xstatus(path)
        send_xstatus path
    end

    protected

    # Perform the actual command execution - this allows device implementations
    # to protect access to #xcommand and still refer the gruntwork here.
    def send_xcommand(command, args = {})
        request = Xapi::Action.xcommand command, args

        do_send request, name: command do |response|
            # The result keys are a little odd: they're a concatenation of the
            # last two command elements and 'Result', unless the command
            # failed in which case it's just 'Result'.
            # For example:
            #   xCommand Video Input SetMainVideoSource ...
            # becomes:
            #   InputSetMainVideoSourceResult
            result_key = command.split(' ').last(2).join('') + 'Result'
            command_result = response.dig 'CommandResponse', result_key
            failure_result = response.dig 'CommandResponse', 'Result'

            result = command_result || failure_result

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

    # Apply a single configuration on the device.
    def send_xconfiguration(path, setting, value)
        request = Xapi::Action.xconfiguration path, setting, value

        do_send request, name: "#{path} #{setting}" do |response|
            result = response.dig 'CommandResponse', 'Configuration'

            if result&.[]('status') == 'Error'
                reason = result.dig 'Reason', 'Value'
                xpath = result.dig 'XPath', 'Value'
                logger.error "#{reason} (#{xpath})" if reason
                :abort
            else
                :success
            end
        end
    end

    # Apply a set of configurations.
    def send_xconfigurations(path, settings)
        # The API only allows a single setting to be applied with each request.
        interactions = settings.to_a.map do |(setting, value)|
            send_xconfiguration(path, setting, value)
        end

        thread.finally(interactions).then do |results|
            resolved = results.map(&:last)
            if resolved.all?
                :success
            else
                failures = resolved.zip(settings.keys)
                                   .reject(&:first)
                                   .map(&:last)

                thread.defer.reject 'Could not apply all settings. ' \
                    "Failed on #{failures.join ', '}."
            end
        end
    end

    # Query the device's current status.
    #
    # @param path [String]
    # @yield [response]
    #   a pre-parsed response object for the command, if used this block
    #   should return the response result
    def send_xstatus(path)
        request = Xapi::Action.xstatus path

        defer = thread.defer

        do_send request, name: "? #{path}" do |response|
            path_components = Xapi::Action.tokenize path
            status_response = response.dig 'Status', *path_components
            error_result = response.dig 'CommandResponse', 'Status'

            if status_response
                yield status_response if block_given?
                defer.resolve status_response
                :success
            else
                reason = error_result&.dig 'Reason', 'Value'
                xpath = error_result&.dig 'XPath', 'Value'
                logger.error "#{reason} (#{xpath})" if reason
                defer.reject
                :abort
            end
        end

        defer.promise
    end

    # Subscribe to feedback from the device.
    #
    # @param path [String, Array<String>] the xPath to subscribe to updates for
    # @param update_handler [Proc] a callback to receive updates for the path
    def subscribe(path, &update_handler)
        logger.debug { "Subscribing to device feedback for #{path}" }

        unless subscriptions.contains? path
            request = Xapi::Action.xfeedback :register, path
            # Always returns an empty response, nothing special to handle
            result = do_send request
        end

        subscriptions.insert path, &update_handler

        result || thread.defer.resolve(:success)
    end

    def unsubscribe(path)
        logger.debug { "Unsubscribing feedback for #{path}" }

        subscriptions.remove path

        request = Xapi::Action.xfeedback :deregister, path
        do_send request
    end

    def clear_subscriptions
        unsubscribe '/'
    end

    def subscribe_to_configuration
        subscribe '/Configuration' do |configuration|
            self[:configuration] = configuration
        end

        send "xConfiguration *\n", wait: false
    end

    # Execute raw command on the device.
    #
    # @param command [String] the raw command to execute
    # @param options [Hash] options for the transport layer
    # @yield [response]
    #   a pre-parsed response object for the command, if used this block
    #   should return the response result
    # @return [::Libuv::Q::Promise]
    def do_send(command, **options)
        request_id = generate_request_uuid

        request = "#{command} | resultId=\"#{request_id}\"\n"

        handle_response = lambda do |response|
            if response['ResultId'] == request_id
                if block_given?
                    yield response
                else
                    :success
                end
            else
                :ignore
            end
        end

        logger.debug { "-> #{request}" }

        send request, **options do |response, defer, cmd|
            received response, defer, cmd, &handle_response
        end
    end

    def generate_request_uuid
        SecureRandom.uuid
    end

    def subscriptions
        @subscriptions ||= Util::FeedbackTrie.new
    end

    def register_control_system
        send_xcommand 'Peripherals Connect',
                      ID: self[:peripheral_id],
                      Name: 'ACAEngine',
                      SoftwareInfo: self[:version],
                      Type: :ControlSystem
    end

    def heartbeat(timeout:)
        send_xcommand 'Peripherals HeartBeat',
                      ID: self[:peripheral_id],
                      Timeout: timeout
    end

    def edge_id
        @edge_id ||= @__config__.settings.edge_id
    end

    def version
        if system 'git --version'
            Dir.chdir(__dir__) { `git rev-parse --short HEAD`.strip }
        else
            'Unknown'
        end
    end
end
