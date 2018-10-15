require 'savon'
require 'active_support/time'
require 'digest/md5'
module Loqit; end

# require 'loqit/lockers'
# lockers = Loqit::Lockers.new(
#     username: 'xmltester',
#     password: 'xmlPassword',
#     wsdl: 'http://10.224.8.2/soap/server_wsdl.php?wsdl',
#     serial: 'BE434080-7277-11E3-BC4D-94C69111930A'
# )
# all_lockers = lockers.list_lockers_detailed

# random_locker = all_lockers.sample
# locker_number = random_locker['number']
# locker_number = '31061'
# locker_number = '31025'
# locker_number = '30914'
# random_locker_status = lockers.show_locker_status(locker_number)
# random_locker_available = random_locker_status['LockerState']



# open_status = lockers.open_locker(locker_number)

# random_locker = lockers.list_lockers.sample['number']
# random_status = lockers.show_status(random_locker)
# random_open = lockers.open_locker(random_locker)



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
            :wsdl => wsdl,
            :log => log,
            :log_level => log_level
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
        ).body[:list_lockers_response][:return]
        JSON.parse(response)
    end

    def list_lockers_detailed(start_number:nil, end_number:nil)
        all_lockers_detailed = []
        puts "STARTING LOCKER GET"
        if start_number
            (start_number.to_i..end_number.to_i).each do |num|
                all_lockers_detailed.push(self.show_locker_status(num.to_s))
            end
        else
            all_lockers = self.list_lockers
            all_lockers.each_with_index do |locker, ind|
                all_lockers_detailed.push(self.show_locker_status(locker['number']))
            end
        end
        puts "FINISHED LOCKER GET"
        all_lockers_detailed
    end

    def show_locker_status(locker_number)
        response = @client.call(:show_locker_status,
            message: {
                lockerNumber: locker_number,
                unitSerial:  @serial
            },
            soap_header: @header
        ).body[:show_locker_status_response][:return]
        JSON.parse(response)
    end

    def open_locker(locker_number)   
        response = @client.call(:open_locker,
            message: {
                lockerNumber: locker_number
            },
            soap_header: @header
        ).body[:locker_number_response][:return]
        JSON.parse(response)
    end

    def store_credentials(locker_number, user_pin_code, user_card, test_if_free=false)   
        payload = {
            lockerNumber: locker_number,
            userPincode: user_pin_code
        }
        payload[:userCard] = user_card if user_card
        payload[:testIfFree] = test_if_free
        response = @client.call(:store_credentials,
            message: payload,
            soap_header: @header
        ).body[:store_credentials_response][:return]
        JSON.parse(response)
    end

    def customer_has_locker(user_card)   
        response = @client.call(:customer_has_locker,
            message: {
                lockerNumber: locker_number,
                unitSerial:  @serial
            },
            soap_header: @header
        ).body[:customer_has_locker_response][:return]
        JSON.parse(response)
    end

end