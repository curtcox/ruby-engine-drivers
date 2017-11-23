Orchestrator::Testing.mock_device 'Cisco::Spark::RoomOs' do
    # Intercept calls to the request id generation so we can run tests.
    @manager.instance.class_eval do
        generate_uuid = instance_method(:generate_request_uuid)

        define_method(:generate_request_uuid) do
            generate_uuid.bind(self).call.tap do |id|
                instance_variable_set :@__last_uuid, id
            end
        end
    end

    def last_uuid
        @manager.instance.instance_variable_get :@__last_uuid
    end

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
        .should_send("xCommand Standby Deactivate | resultId=\"#{last_uuid}\"\n")
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "StandbyDeactivateResult":{
                            "status":"OK"
                        }
                    },
                    "ResultId": \"#{last_uuid}\"
                }
            JSON
        )

    # Command with arguments
    exec(:xcommand, 'Video Input SetMainVideoSource', ConnectorId: 1, Layout: :PIP)
        .should_send("xCommand Video Input SetMainVideoSource ConnectorId: 1 Layout: PIP | resultId=\"#{last_uuid}\"\n")
        .responds(
            <<~JSON
                {
                    "CommandResponse":{
                        "InputSetMainVideoSourceResult":{
                            "status":"OK"
                        }
                    },
                    "ResultId": \"#{last_uuid}\"
                }
            JSON
        )

    # Return device argument errors
    exec(:xcommand, 'Video Input SetMainVideoSource', ConnectorId: 1, SourceId: 1)
        .should_send("xCommand Video Input SetMainVideoSource ConnectorId: 1 SourceId: 1 | resultId=\"#{last_uuid}\"\n")
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
                    "ResultId": \"#{last_uuid}\"
                }
            JSON
        )
end
