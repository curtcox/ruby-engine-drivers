Orchestrator::Testing.mock_device 'Wolfvision::Eye14' do
    exec(:power?)
        .should_send("*power ?\r") # power query
        .responds("ack power = 0") # respond with on
        .expect(status[:power]).to be(false)

    exec(:power, true)
        .should_send("*power = 0\r") # power query
        .responds("ack power = 0") # respond with on
        .expect(status[:power]).to be(true)

    exec(:input?)
        .should_send("*input ?\r")
        .responds("ack input = 0") # respond with on
        .expect(status[:input]).to be(:display_port)

    exec(:switch_to, "hdmi")
        .should_send("*input = 1\r")
        .responds("ack input = 1") # respond with on
        .expect(status[:input]).to be(:hdmi)

    exec(:freeze?)
        .should_send("*freeze ?\r") # power query
        .responds("ack freeze = 0") # respond with on
        .expect(status[:freeze]).to be(false)

    exec(:freeze, true)
        .should_send("*freeze = 1\r") # power query
        .responds("ack power = 1") # respond with on
        .expect(status[:freeze]).to be(true)
end
