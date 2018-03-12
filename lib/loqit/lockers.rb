require 'savon'
require 'active_support/time'
require 'digest/md5'
module Loqit; end


# lockers_client = Loqit::Lockers.new(
#     username: 'system',
#     password: 'system',
#     endpoint: 'https://DESKTOP-ABH46ML:8082/Cardholder/',
#     namespace: 'http://www.gallagher.co/security/commandcentre/webservice',
#     namespaces: {"xmlns:wsdl" => "http://www.gallagher.co/security/commandcentre/cifws", "xmlns:web" => 'http://www.gallagher.co/security/commandcentre/webservice'},
#     wsdl: 'http://192.168.1.200/soap/server_wsdl.php?wsdl',
#     log: false,
#     log_level: nil
#     )

class Loqit::Lockers
    def initialize(
            username:,
            password:,
            serial:,
            wsdl:,
            log: false,
            log_level: :debug
        )
        savon_config = {
            :wsdl => wsdl
        }

        @client = Savon.client savon_config
        @username = username
        @password = password
        @serial = serial
        @header = {
            header: {
                username: @username,
                password: Digest::MD5.hexdigest(@password),
                serialnumber: @serial
            }
        }
    end
    def list_lockers
        response = @client.call(:list_lockers,
            message: {
                unitSerial: @serial
            },
            soap_header: @header
        )
    end

end

