Orchestrator::Testing.mock_device 'TvOne::CorioMaster',
                                  settings: {
                                      username: 'admin',
                                      password: 'adminpw'
                                  } do
    transmit <<~INIT
        // ===================\r
        //  CORIOmaster - CORIOmax\r
        // ===================\r
        // Command Interface Ready\r
        Please login. Use 'login(username,password)'\r
    INIT

    should_send "login(admin,adminpw)\r\n"
    responds "!Info : User admin Logged In\r\n"
    expect(status[:connected]).to be(true)

    should_send "CORIOmax.Serial_Number\r\n"
    responds <<~RX
        CORIOmax.Serial_Number = 2218031005149\r
        !Done CORIOmax.Serial_Number\r
    RX
    expect(status[:serial_number]).to be(2218031005149)

    should_send "CORIOmax.Software_Version\r\n"
    responds <<~RX
        CORIOmax.Software_Version = V1.30701.P4 Master\r
        !Done CORIOmax.Software_Version\r
    RX
    expect(status[:firmware]).to eq('V1.30701.P4 Master')

    exec(:preset, 1)
        .should_send("Preset.Take = 1\r\n")
        .responds <<~RX
            Preset.Take = 1\r
            !Done Preset.Take\r
        RX
    wait_tick
    expect(status[:preset]).to be(1)
end
