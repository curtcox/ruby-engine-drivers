# encoding: ASCII-8BIT
# frozen_string_literal: true

# rake offload:catalyst_snmp['port_number']

namespace :offload do
    desc 'provides a process for offloading SNMP workloads'
    task(:catalyst_snmp, [:tcp_port]) do |_, args|
        require 'uv-rays'
        require File.join(__dir__, '../../modules/cisco/catalyst_snmp_client.rb')
        require File.join(__dir__, '../../modules/cisco/catalyst_offloader.rb')

        port = args[:tcp_port].to_i
        puts "offload catalyst snmp binding to port #{port}"

        Libuv.reactor.run do |reactor|
            tcp = reactor.tcp
            tcp.bind('127.0.0.1', port) do |client|
                tokeniser = ::UV::AbstractTokenizer.new(::Cisco::CatalystOffloader::ParserSettings)
                snmp_client = nil

                client.progress do |data|
                    tokeniser.extract(data).each do |response|
                        begin
                            args = Marshal.load(response)
                            if args[0] == :client
                                snmp_client&.close
                                snmp_client = ::Cisco::Switch::CatalystSNMPClient.new(reactor, args[1])
                            else
                                retval = snmp_client.__send__(*args)
                                if args[0].to_s.start_with? 'query'
                                    msg =  Marshal.dump(retval)
                                    client.write("#{[msg.length].pack('V')}#{msg}")
                                end
                            end
                        rescue => e
                            STDOUT.puts "failed to marshal request\n#{e.message}\n#{e.backtrace.join("\n")}"
                        end
                    end
                end
                client.start_read
            end
            tcp.catch do |e|
                STDOUT.puts "failed to bind port\n#{e.message}\n#{e.backtrace.join("\n")}"
            end
        end

        puts "offload catalyst snmp closed..."
    end
end
