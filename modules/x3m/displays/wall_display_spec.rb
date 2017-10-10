# encoding: ASCII-8BIT

# Syntactic sugar so the helper module tests stick to a common format
def describe(item)
    depth = if caller(1..1).first =~ /block \((\d+) levels\) in/
                Regexp.last_match(1).to_i - 1
            else
                0
            end

    puts '' if depth == 0
    puts ' ' * depth + item
    yield
end

Orchestrator::Testing.mock_device 'X3m::Displays::WallDisplay' do
    describe 'Util module' do
        Util = X3m::Displays::WallDisplay::Util

        describe '.encode' do
            expect(Util.encode(10, length: 2)).to eq [0x30, 0x41]
        end

        describe '.decode' do
            expect(Util.decode('0A')).to eq 10
            expect(Util.decode('A')).to eq 0x41
        end

        describe '.scale' do
            expect(Util.scale(10, 100, 1000)).to eq 100
        end

        describe '.bidirectional' do
            expect(Util.bidirectional({a: 1})).to eq({a: 1, 1 => :a})
        end

        describe '.dig' do
            hash = {
                a: {
                    b: 1
                }
            }
            expect(Util.dig(hash, :a, :b)).to eq 1
            expect(Util.dig(hash, :c, :b)).to be_nil
        end
    end

    describe "Protocol module" do
        Protocol = X3m::Displays::WallDisplay::Protocol

        describe '.lookup' do
            expect(Protocol.lookup(:power, true)).to eq [0x3, 1]
        end

        describe '.resolve' do
            expect(Protocol.resolve(0x3, 1)).to eq [:power, true]
        end

        describe '.build_packet' do
            verification_packet = "\x010*0E0A\x0200030001\x03\x1d\r".bytes
            constructed_packet = Protocol.build_packet(0x3, 1)
            expect(constructed_packet).to eq verification_packet
        end

        describe '.parse_response' do
            power_on_rx = "\x0100*F12\x020000030000010001\x03\x6d\r"
            response = Protocol.parse_response power_on_rx
            expected_response = {
                receiver: :pc,
                monitor_id: :all,
                message_type: :set_parameter_reply,
                success: true,
                command: :power,
                value: true
            }
            expect(response).to eq expected_response

            invalid_rx = 'hail hypnotoad'
            expect { Protocol.parse_response invalid_rx }.to raise_error 'invalid packet structure'
        end
    end

    describe 'Testing device interaction' do
        exec(:power, true, priority: 0)
            .should_send("\x010*0E0A\x0200030001\x03\x1d\r")
            .responds("\x0100*F12\x020000030000010001\x03\x6d\r")
        expect(status[:power]).to be true
        expect(status[:power_target]).to be true

        exec(:power, false)
            .should_send("\x010*0E0A\x0200030000\x03\x1c\r")
            .responds("\x0100*F12\x020000030000010000\x03\x6c\r")
        expect(status[:power]).to be false
        expect(status[:power_target]).to be false
    end
end
