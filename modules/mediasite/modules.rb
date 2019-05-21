# frozen_string_literal: true

require 'net/http'

module Mediasite; end

class Mediasite::Module
    descriptive_name 'Mediasite'
    generic_name :Recorder
    implements :logic

    default_settings(
        url: 'https://alex-dev.deakin.edu.au/Mediasite/',
        username: 'acaprojects',
        password: 'WtjtvB439cXdZ4Z3'
    )

    def on_load
        on_update
    end

    def on_update
    end

    def request(url)
        uri = URI.parse(url)
        request = Net::HTTP::GET.new(URI.parse(uri))
        request.basic_auth(setting(:username), setting(:password))
        http = Net::HTTP.new(uri.host, uri.port)
        response = http.request(request)
    end

    # https://alex.deakin.edu.au/mediasite/api/v1/$metadata#Rooms
    # GET /api/v1/Room
    # GET /api/v1/Rooms('id')
    def get_rooms
        request(url + '/api/v1/Room')
    end

    STATES = {
        'Unknown' => 'Offline',
        'Idle' => 'Idle',
        'Busy' => 'Recording',
        'RecordStart' => 'Recording',
        'Recording' => 'Recording',
        'RecordEnd' => 'Recording',
        'Pausing' => 'Recording',
        'Paused' => 'Recording',
        'Resuming' => 'Recording',
        'OpeningSession' => 'Recording',
        'ConfiguringDevices' => 'Idle'
    }.freeze

    # State tracking of recording appliance. While there are numerous recorder states (currently 11 different states), we wish to present these as a simplified state set: Offline, Idle, Recording, Paused.
    def state
    end
end
