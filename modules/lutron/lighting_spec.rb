EngineSpec.mock_device "Lutron::Lighting" do
    # Module waits for this text to become ready
    transmit "login: "
    should_send "nwk\r\n"
    transmit "connection established\r\n"

    sleep 110.milliseconds

    # Perform actions
    exec(:scene?, 1)
    should_send("?AREA,1,6\r\n")
    responds("~AREA,1,6,2\r\n")
    expect(status[:area1]).to be(2)

    transmit "~DEVICE,1,6,9,1\r\n"
    expect(status[:device1_6_led]).to be(1)

    transmit "~AREA,1,6,1\r\n"
    expect(status[:area1]).to be(1)

    transmit "~OUTPUT,53,1,100.00\r\n"
    expect(status[:output53_level]).to be(100.00)

    transmit "~SHADEGRP,26,1,100.00\r\n"
    expect(status[:shadegrp26_level]).to be(100.00)

    sleep 110.milliseconds

    exec(:scene, 1, 3)
    should_send("#AREA,1,6,3\r\n")
    responds("\r\n")

    sleep 110.milliseconds

    should_send("?AREA,1,6\r\n")
    transmit "~AREA,1,6,3\r\n"

    expect(status[:area1]).to be(3)
end
