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

Orchestrator::Testing.mock_device 'Clipsal::DaliControl' do
    describe "Protocol module" do
        Protocol = Clipsal::DaliControl::Protocol

        describe '.build_packet' do
            verification_packet = '$001014003000*'
            constructed_packet = Protocol.build_packet 1, :dali, '0', '0', '0'
            expect(constructed_packet).to eq verification_packet
        end

        describe '.build_group_packet' do
            verification_packet = '$0710150070038000*'
            constructed_packet = Protocol.build_group_packet 71, :line_a, 3, :dali_action, :off
            expect(constructed_packet).to eq verification_packet
        end

        describe '.build_dali_packet' do
            verification_packet = '$0710140100100321010*'
            constructed_packet = Protocol.build_dali_packet 71, :line_a, 3, :ballast, :arc_level, 10
            expect(constructed_packet).to eq verification_packet
        end
    end

    describe 'Testing device interaction' do
        exec(:off, 71, :line_a, 3)
            .should_send("$0710150070038000*")

        wait 50

        exec(:max, 71, :line_a, 3)
            .should_send("$0710150070038005*")

        wait 50

        exec(:recall_scene, 71, :line_a, 3, 2)
            .should_send("$0710150070038011*")
    end
end
