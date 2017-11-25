require 'thread'

Orchestrator::Testing.mock_device 'Cisco::Spark::RoomOs' do
    # Patch in some tracking of request UUID's so we can form and validate
    # device comms.
    @manager.instance.class_eval do
        generate_uuid = instance_method(:generate_request_uuid)

        attr_accessor :__request_ids

        define_method(:generate_request_uuid) do
            generate_uuid.bind(self).call.tap do |id|
                @__request_ids ||= Queue.new
                @__request_ids << id
            end
        end
    end

    def request_ids
        @manager.instance.__request_ids
    end

    def id_peek
        @last_id || request_ids.pop(true).tap { |id| @last_id = id }
    end

    def id_pop
        @last_id.tap { @last_id = nil } || request_ids.pop(true)
    end

    def section(message)
        puts "\n\n#{'-' * 80}"
        puts message
        puts "\n"
    end

    # -------------------------------------------------------------------------
    section 'Connection setup'

    transmit <<~BANNER
        Welcome to
        Cisco Codec Release Spark Room OS 2017-10-31 192c369
        SW Release Date: 2017-10-31
        *r Login successful

        OK

    BANNER

    expect(status[:connected]).to be true

    should_send "Echo off\n"
    should_send "xPreferences OutputMode JSON\n"


    # -------------------------------------------------------------------------
    section 'Base comms (protected methods - ignore the access warnings)'

    # Append a request id and handle generic response parsing
    exec(:do_send, 'xCommand Standby Deactivate')
        .should_send("xCommand Standby Deactivate | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "StandbyDeactivateResult":{
                            "status":"OK"
                        }
                    },
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
    expect(result).to be :success

    # Handle invalid device commands
    exec(:do_send, 'Not a real command')
        .should_send("Not a real command | resultId=\"#{id_pop}\"\n")
        .responds("Command not recognized.\n")
    expect { result }.to raise_error(Orchestrator::Error::CommandFailure)

    # Handle async response data
    exec(:do_send, 'xCommand Standby Deactivate')
        .should_send("xCommand Standby Deactivate | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "RandomAsyncData": "Foo"
                }
            JSON
        )
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "StandbyDeactivateResult":{
                            "status":"OK"
                        }
                    },
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
    expect(result).to be :success

    # Device event subscription
    exec(:subscribe, '/Status/Audio/Microphones/Mute')
        .should_send("xFeedback register /Status/Audio/Microphones/Mute | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
    expect(result).to be :success


    # -------------------------------------------------------------------------
    section 'Commands'

    # Basic command
    exec(:xcommand, 'Standby Deactivate')
        .should_send("xCommand Standby Deactivate | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "StandbyDeactivateResult":{
                            "status":"OK"
                        }
                    },
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
    expect(result).to be :success

    # Command with arguments
    exec(:xcommand, 'Video Input SetMainVideoSource', ConnectorId: 1, Layout: :PIP)
        .should_send("xCommand Video Input SetMainVideoSource ConnectorId: 1 Layout: PIP | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "InputSetMainVideoSourceResult":{
                            "status":"OK"
                        }
                    },
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
    expect(result).to be :success

    # Return device argument errors
    exec(:xcommand, 'Video Input SetMainVideoSource', ConnectorId: 1, SourceId: 1)
        .should_send("xCommand Video Input SetMainVideoSource ConnectorId: 1 SourceId: 1 | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "InputSetMainVideoSourceResult":{
                            "status":"Error",
                            "Reason":{
                                "Value":"Must supply either SourceId or ConnectorId (but not both.)"
                            }
                        }
                    },
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
    expect { result }.to raise_error(Orchestrator::Error::CommandFailure)

    # Return error from invalid / inaccessable xCommands
    exec(:xcommand, 'Not A Real Command')
        .should_send("xCommand Not A Real Command | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "Result":{
                            "status":"Error",
                            "Reason":{
                                "Value":"Unknown command"
                            }
                        },
                        "XPath":{
                            "Value":"/Not/A/Real/Command"
                        }
                    },
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
    expect { result }.to raise_error(Orchestrator::Error::CommandFailure)


    # -------------------------------------------------------------------------
    section 'Configuration'

    # Basic configuration
    exec(:xconfiguration, 'Video Input Connector 1', InputSourceType: :Camera)
        .should_send("xConfiguration Video Input Connector 1 InputSourceType: Camera | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
    expect(result).to match_array [:success]

    # Multuple settings
    exec(:xconfiguration, 'Video Input Connector 1', InputSourceType: :Camera, Name: "Borris", Quality: :Motion)
        .should_send("xConfiguration Video Input Connector 1 InputSourceType: Camera | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
        .should_send("xConfiguration Video Input Connector 1 Name: \"Borris\" | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
        .should_send("xConfiguration Video Input Connector 1 Quality: Motion | resultId=\"#{id_peek}\"\n")
        .responds(
            <<~JSON
                {
                    "ResultId": \"#{id_pop}\"
                }
            JSON
        )
    expect(result).to match_array [:success, :success, :success]
end
