Orchestrator::Testing.mock_device 'Wolfvision::Eye14' do
=begin
    should_send("\x00\x30\x00")
    transmit("\x00\x30\x01\x00") # tell driver device is off
=end
    exec(:power?)
        .should_send("\x00\x30\x00") # power query
        .responds("\x00\x30\x01\x01") # respond with on
        .expect(status[:power]).to be(true)

    wait(150)

    exec(:power, false)
        .should_send("\x01\x30\x01\x00") # turn off device
        .responds("\x01\x30\x00") # respond with success
        .expect(status[:power]).to be(false)

    wait(150)

    exec(:zoom, 6)
        .should_send("\x01\x20\x02\x00\x06")
        .transmit("\x01\x20\x00")

=begin
    exec(:zoom, 6)
        .should_send("\x01\x20\x02\x00\x06")
        .transmit("\x01\x20\x00")

    transmit("anything")
=begin
    expect(status[:power]).to be(true)

    exec(:zoom, 6)
    transmit("\x00\x20\x00")
=end

=begin
    exec(:power, false) # turn on the device
        .should_send("\x01\x30\x01\x00")
        .responds("\x01\x30\x00")

    exec(:zoom, 6)
        .should_send("\x01\x20\x02\x00\x06")
        .responds("\x00\x20\x00")


    exec(:power?)
        .should_send("\x00\x30\x00") # power query
        .responds("\x00\x30\x01\x01") # respond with on
        .expect(status[:power]).to be(true)

    exec(:power, false) # turn off the device
    transmit("\x00\x30\x01\x00") # respond with off
    expect(status[:power]).to be(false)

    exec(:autofocus?)
    transmit("\x00\x31\x01\x00") # respond with off
    expect(status[:autofocus]).to be(false)

    exec(:zoom?)
        .should_send("\x00\x20\x00")
        .responds("\x00\x20\x02\xFF\xFF")

    exec(:zoom, "\xFF\xFF")
        .should_send("\x01\x20\x02\xFF\xFF")
        .responds("\x00\x20\x00")

    exec(:iris, 0xFFFF)
        .should_send("\x01\x22\x02\xFF\xFF")
        .responds("\x00\x22\x00")
=end
end
