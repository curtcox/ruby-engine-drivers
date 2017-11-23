Orchestrator::Testing.mock_device 'Cisco::Spark::RoomOs' do
    transmit <<~BANNER
        Welcome to
        Cisco Codec Release Spark Room OS 2017-10-31 192c369
        SW Release Date: 2017-10-31
        *r Login successful

        OK

    BANNER

    expect(status[:connected]).to be true

    # Comms setup
    should_send "Echo off\n"
    should_send "xPreferences OutputMode JSON\n"

    # Basic command
    exec(:xcommand, 'Standby Deactivate')
        .should_send("xCommand Standby Deactivate | resultId=\"#{status[:__last_uuid]}\"\n")
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "StandbyDeactivateResult":{
                            "status":"OK"
                        }
                    },
                    "ResultId": \"#{status[:__last_uuid]}\"
                }
            JSON
        )

    # Command with arguments
    exec(:xcommand, 'Video Input SetMainVideoSource', ConnectorId: 1, Layout: :PIP)
        .should_send("xCommand Video Input SetMainVideoSource ConnectorId: 1 Layout: PIP | resultId=\"#{status[:__last_uuid]}\"\n")
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "InputSetMainVideoSourceResult":{
                            "status":"OK"
                        }
                    },
                    "ResultId": \"#{status[:__last_uuid]}\"
                }
            JSON
        )

    # Return device argument errors
    exec(:xcommand, 'Video Input SetMainVideoSource', ConnectorId: 1, SourceId: 1)
        .should_send("xCommand Video Input SetMainVideoSource ConnectorId: 1 SourceId: 1 | resultId=\"#{status[:__last_uuid]}\"\n")
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
                    "ResultId": \"#{status[:__last_uuid]}\"
                }
            JSON
        )
end
