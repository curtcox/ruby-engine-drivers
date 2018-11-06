# encoding: ASCII-8BIT
# frozen_string_literal: true

Orchestrator::Testing.mock_device 'Ricoh::D6500' do
    exec(:power, true)
        .should_send("\x38\x30\x32\x73\x21\x30\x30\x31\x0D") # power on
        .responds("\x34\x30\x32\+\r")
        .expect(status[:power]).to be(true)

    exec(:power?)
        .should_send("\x38\x30\x32\x67\x6C\x30\x30\x30\r") # power query
        .responds("\x38\x30\x32\x72\x6C\x30\x30\x30\r")
        .expect(status[:power]).to be(false)

    exec(:input?)
        "\x38\x30\x32\x67\x6A\x30\x30\x30\x0D"
        .should_send("\x38\x30\x32\x67\x88\x30\x30\x30\r") # power query
        .responds("\x38\x30\x32\x72\x88\x30\x30\x31\r")
        .expect(status[:input]).to be('hdmi')
end
