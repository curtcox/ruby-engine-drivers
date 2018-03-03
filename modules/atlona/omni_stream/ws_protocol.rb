# encoding: ASCII-8BIT
# frozen_string_literal: true

require 'protocols/websocket'

module Atlona; end
module Atlona::Omnistream; end

# Configuring input 2 on the atlona
# HDMI config set: {"id":"hdmi_input","username":"admin","password":"Atlona","config_set":{"name":"hdmi_input","config":[{"audio":{"active":false,"bitdepth":0,"channelcount":0,"codingtype":"Unknown","samplingfrequency":"unknown"},"cabledetect":false,"edid":"Default","hdcp":{"encrypted":false,"support_version":"1.4"},"name":"hdmi_input2","video":{},"number":2,"hdcpSupportVersion":true}]}}
# Response: {"error": false, "id": "hdmi_input"}

class Atlona::Omnistream::WsProtocol
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security

    # supports encoders and decoders
    descriptive_name 'Atlona Omnistream WS Protocol'
    generic_name :Decoder

    tcp_port 80
    wait_response false

    def on_load
        on_update
    end


    # Encoder
    # hdmi_input => are the sources connected
    # sessions => 1,2,3,4
    #          => audio + video streams and addresses + ports
    #
    # ip_input => 1,2,3,4,5
    #          => hdmi_output -- select an input + output
    Query = {}
    [
        :systeminfo, :alarms, :hdmi_input, :sessions, :ip_input, :hdmi_output
    ].each do |cmd|
        # Cache the query strings
        # Remove the leading '{' character
        Queries[cmd] = {
            id: cmd,
            config_get: cmd
        }.to_json[1..-1]

        # generate the query functions
        define_method cmd do
            @ws.text("#{@auth}#{Query[cmd]}")
        end
    end

    # Called after dependency reload and settings updates
    def on_update
        @username = setting(:username) || 'admin'
        @password = setting(:password) || 'Atlona'

        # We'll pair auth with a query to send a command
        @auth = {
            username: @username,
            password: @password
        }.to_json[0..-2]

        # The output this module is interested in
        @num_outputs = (setting(:num_outputs) || 1).to_i
    end

    def connected
        new_websocket_client
    end

    def disconnected
        # clear the keepalive ping
        schedule.clear
    end

    protected

    def query(cmd)
        
    end

    def new_websocket_client
        # NOTE:: you must use wss:// when using port 443 (TLS connection)
        protocol = secure_transport? ? 'wss' : 'ws'
        @ws = Protocols::Websocket.new(self, "#{protocol}://#{remote_address}/wsapp/")
        @ws.start
    end

    def received(data, resolve, command)
        @ws.parse(data)
        :success
    end

    # ====================
    # Websocket callbacks:
    # ====================

    # websocket ready
    def on_open
        logger.debug { "Websocket connected" }

        schedule.every('30s') do
            system_info
            alarms
        end
    end


    def on_message(raw_string)
        logger.debug { "received: #{raw_string}" }
        resp = JSON.parse(raw_string, symbolize_names: true)

        # Warn if there was an error
        if resp[:error]
            logger.warn raw_string
            return
        end

        data = resp[:config]

        # Return if config was successfully updated
        return if data.nil?

        case resp[:id]
        when 'systeminfo'
            self[:type] = data[:type]
            self[:temperature] = data[:temperature]
            self[:model] = data[:model]
            self[:firmware] = data[:firmwareversion]
            self[:uptime] = data[:uptime]
        when 'alarms'
            self[:alarms] = data
        when 'hdmi_input'
            data.each do |input|
                self[input[:name]] = input
            end
        end
    end

    def on_ping(payload)
        logger.debug { "received ping: #{payload}" }
        # optional
    end

    def on_pong(payload)
        logger.debug { "received pong: #{payload}" }
        # optional
    end

    # connection is closing
    def on_close(event)
        logger.debug { "closing... #{event.code} #{event.reason}" }
    end

    # connection is closing
    def on_error(error)
        logger.debug { "ERROR! #{error.message}" }
    end

    # ====================
end
