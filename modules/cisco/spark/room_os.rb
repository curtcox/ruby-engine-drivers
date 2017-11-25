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

    tokenize delimiter: /(?<=\n})|(?<=\n{})|(?<=Command not recognized.)\n/,
             wait_ready: "*r Login successful\n\nOK\n\n"
    clear_queue_on_disconnect!

    def on_load; end

    def on_unload; end

    def on_update; end

    def connected
        send "Echo off\n", wait: false, priority: 96
        send "xPreferences OutputMode JSON\n", wait: false
    end

    def disconnected
        clear_subscriptions!
    end

    # Handle all incoming data from the device.
    #
    # In addition to acting an the normal Orchestrator callback, on_receive
    # blocks also pipe through here for initial JSON decoding. See #do_send.
    def received(data, deferrable, command)
        logger.debug { "<- #{data}" }

        response = JSON.parse data, object_class: CaseInsensitiveHash

        if block_given?
            # Let any pending command response handlers have first pass...
            yield(response).tap do |command_result|
                # Otherwise support interleaved async events
                unprocessed = command_result == :ignore || command_result.nil?
                handle_async response if unprocessed
            end
        else
            handle_async response
            :ignore
        end
    rescue JSON::ParserError => error
        if data.strip == 'Command not recognized.'
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
    def xcommand(command, args = {})
        send_xcommand command, args
    end

    # Push a configuration settings to the device.
    #
    # @param path [String] the configuration path
    # @param settings [Hash] the configuration values to apply
    def xconfiguration(path, settings)
        send_xconfiguration path, settings
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

    def send_xconfiguration(path, settings)
        # The device API only allows a single setting to be applied with each
        # request.
        interactions = settings.to_a.map do |(setting, value)|
            request = Xapi::Action.xconfiguration path, setting, value

            do_send request, name: "#{path} #{setting}" do |response|
                result = response.dig 'CommandResponse', 'Configuration'

                if result&.[] 'status' == 'Error'
                    reason = result.dig 'Reason', 'Value'
                    logger.error reason if reason
                    :abort
                else
                    :success
                end
            end
        end

        thread.all(interactions).then do |results|
            results.all? { |result| result == :success } ? :success : results
        end
    end

    # Subscribe to feedback from the device.
    #
    # @param path [String, Array<String>] the xPath to subscribe to updates for
    # @param update_handler [Proc] a callback to receive updates for the path
    def subscribe(path, &update_handler)
        logger.debug { "Subscribing to device feedback for #{path}" }

        request = Xapi::Action.xfeedback :register, path

        # Build up a Trie based on the path components
        @subscriptions ||= {}
        path_components = xpath_split path
        path_components.reduce(@subscriptions) do |node, component|
            node[component] ||= {}
        end

        # And insert the handler at it's appropriate node
        node = @subscriptions.dig(*path_components)
        node[:_handlers] ||= []
        node[:_handlers] << update_handler

        # Always returns an empty JSON object, no special response to handle
        do_send request
    end

    # Clear all subscribers from a path and deregister device feedback.
    def unsubscribe(path)
        logger.debug { "Unsubscribing feedback for #{path}" }

        request = Xapi::Action.xfeedback :deregister, path

        # Nuke the subtree from the subscription tracker
        path_components = xpath_split path
        if path_components.empty?
            @subscriptions = {}
        else
            node = @subscriptions.dig(*path_components)
            if node.nil?
                logger.warn { "No subscriptions registered for #{path}" }
            else
                *parent_path, node_key = path_components
                parent = if parent_path.empty?
                             @subscriptions
                         else
                             @subscriptions.dig(*parent_path)
                         end
                parent.delete node_key
            end
        end

        do_send request
    end

    # Clears any previously registered device feedback subscriptions
    def clear_subscriptions!
        unsubscribe '/'
    end

    # Split a space or slash seperated path into it's components.
    def xpath_split(path)
        if path.is_a? Array
            path
        else
            path.split(/[\s\/\\]/)
                .reject(&:empty?)
                .map(&:downcase)
                .map(&:to_sym)
        end
    end

    # Execute raw command on the device.
    #
    # Automatically appends a result tag and handles routing of response
    # handling for async interactions. If a block is passed a pre-parsed
    # response object will be yielded to it.
    #
    # @param command [String] the raw command to execute
    # @param options [Hash] options for the transport layer
    # @yield [response]
    #   a pre-parsed response object for the command, if used this block
    #   should return the response result
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

    def handle_async(response)
        logger.debug "Handling async rx for #{response}"

        # Traverse the response where there are any subscriptions registered
        notify = lambda do |subscriptions, resp|
            resp.each do |key, subtree|
                subpath = key.downcase.to_sym
                next unless subscriptions.key? subpath
                handlers = subscriptions.dig subpath, :_handlers
                [*handlers].each { |handler| handler.call subtree }
                notify.call subscriptions[subpath], subtree
            end
        end

        notify.call @subscriptions, response
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
