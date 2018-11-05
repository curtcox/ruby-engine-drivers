# encoding: ASCII-8BIT
# frozen_string_literal: true

Orchestrator::Testing.mock_device 'Ricoh::D6500' do
    exec(:power, true)
        .should_send("\x38\x30\x32\x73\x30\x30\x31\x0D") # power on
        .responds("\+\x38\x30\x32\x21\r")
end
