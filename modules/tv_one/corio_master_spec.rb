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

    exec(:exec, 'System.Reset')
        .should_send("System.Reset()\r\n")
        .responds <<~RX
            !Info: Rebooting...\r
        RX
    expect(result).to be(:success)

    exec(:set, 'Window1.Input', 'Slot3.In1')
        .should_send("Window1.Input = Slot3.In1\r\n")
        .responds <<~RX
            Window1.Input = Slot3.In1\r
            !Done Window1.Input\r
        RX
    expect(result).to be(:success)

    exec(:query, 'Window1.Input', expose_as: :status_var_test)
        .should_send("Window1.Input\r\n")
        .responds <<~RX
            Window1.Input = Slot3.In1\r
            !Done Window1.Input\r
        RX
    expect(result).to be(:success)
    expect(status[:status_var_test]).to eq('Slot3.In1')

    exec(:preset, 1)
        .should_send("Preset.Take = 1\r\n")
        .responds <<~RX
            Preset.Take = 1\r
            !Done Preset.Take\r
        RX
    wait_tick
    expect(result).to be(:success)
    expect(status[:preset]).to be(1)
end
