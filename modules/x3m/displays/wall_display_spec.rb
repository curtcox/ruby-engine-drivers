# encoding: ASCII-8BIT

Orchestrator::Testing.mock_device 'X3m::Displays::WallDisplay' do
    # TODO: form propper response string
    exec(:power, true)
        .should_send("\x010*0E0A\x0200030001\x03\x1c\r")
        .responds("\x0100*F12\x020000030000010001\x03\x1c\r")
    expect(status[:power]).to be true

    exec(:power, false)
        .should_send("\x010*0E0A\x0200030000\x03\x1d\r")
        .responds("\x0100*F12\x020000030000010001\x03\x1c\r")
    expect(status[:power]).to be false
end
