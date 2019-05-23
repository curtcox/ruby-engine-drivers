# frozen_string_literal: true

require 'net/http'
require 'json'

module Mediasite; end

class Mediasite::Module
    include ::Orchestrator::Constants

    descriptive_name 'Mediasite Recorder'
    generic_name :Recorder
    implements :logic

    default_settings(
        # url: 'https://alex-dev.deakin.edu.au/Mediasite/' # api url endpoint
        # username:
        # password:
        # api_key: # sfapikey
        # actual_room_name: setting to override room name to search when they mediasite room names don't match up wtih backoffice system names
        update_every: 1
    )

    def on_load
        on_update
    end

    def on_update
        schedule.clear
        self[:room_name] = room_name
        self[:device_id] = get_device_id
    end

    def room_name
        setting(:actual_room_name) || system.name
    end

    def start
        schedule.every("#{setting(:update_every)}m") do
            state
        end
    end

    def poll
    end

    def get_request(url)
        req_url = setting(:url) + url
        logger.debug(req_url)
        uri = URI(req_url)
        req = Net::HTTP::Get.new(uri)
        req.basic_auth(setting(:username), setting(:password))
        req['sfapikey'] = setting(:api_key)
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true
        JSON.parse(http.request(req).body)
    end

    def get_device_id
        # Use $top=1000 to ensure that all rooms are returned from the api
        res = get_request('api/v1/Rooms?$top=1000')
        res['value'].each { |room|
            if room['Name'] == room_name
                return room['DeviceConfigurations'][0]['DeviceId']
            end
        }
    end

    def get_device
        res = get_request("api/v1/Recorders('#{self[:device_id]}')")
        logger.debug res
        res
    end

    def post_request(url)
        req_url = setting(:url) + url
        logger.debug(req_url)
        uri = URI(req_url)
        req = Net::HTTP::Post.new(uri)
        req.basic_auth(setting(:username), setting(:password))
        req['sfapikey'] = setting(:api_key)
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true
        JSON.parse(http.request(req).body)
    end

    # State tracking of recording appliance. While there are numerous recorder states (currently 11 different states), we wish to present these as a simplified state set: Offline, Idle, Recording, Paused.
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

    # GET /api/v1/Recorders('id')/Status
    def state
        res = get_request("/api/v1/Recorders('#{self[:device_id]}')/Status")
        self[:previous_state] = self[:state]
        self[:state] = STATES[res['RecorderState']]
        res = get_request("/api/v1/Recorders('#{self[:device_id]}')/CurrentPresentationMetadata")
        self[:title] = res['Title']
        self[:presenters] = res['Presenters']
        self[:live] = false # TODO: found out how to know if recording is being live streamed
        res = get_request("/api/v1/Recorders('#{self[:device_id]}')/ActiveInputs")
        self[:dual] = res['ActiveInputs'].size >= 2
        res = get_request("/api/v1/Recorders('#{self[:device_id]}')/TimeRemaining")
        self[:time_remaining] = res['SecondsRemaining']
        self[:volume] = 0
    end

=begin
GET /api/v1/Recorders('id')/CurrentPresentationMetadata
Metadata for the current recording including title, start datetime, and if a schedule is available, linked modules and presenter names.
Title - The title of the recording.
Presenters – A list of presenters associated with the recording.
Live – Boolean value indicating that it is also being live streamed.
Dual – Boolean indicating that 2 or more video inputs are being used.
GET /api/v1/Recorders('id')/TimeRemaining
Time Remaining – For scheduled recordings, a mechanism to show how long until the current recording completes. (Discussion with UX team required re whether they would prefer XXX seconds or mm:ss format.)
Basic volume level of current recording. This may be obtained either via the Mediasite API or via QSC.  Further discussion is required to ensure an efficient implementation.  Refer to Potential Constrains section below.
=end

=begin
POST /api/v1/CatchDevices('id')/Start
POST /api/v1/CatchDevices('id')/Stop
POST /api/v1/CatchDevices('id')/Pause
POST /api/v1/CatchDevices('id')/Resume

POST /api/v1/Recorders('id')/Start
POST /api/v1/Recorders('id')/Stop
POST /api/v1/Recorders('id')/Pause
POST /api/v1/Recorders('id')/Resume
=end
    def pause
        if self[:device_id]
            post_request("/api/v1/Recorders('#{self[:device_id]}')/Pause")
        end
    end

    def resume
        if self[:device_id]
            post_request("/api/v1/Recorders('#{self[:device_id]}')/Resume")
        end
    end

    def stop
        if self[:device_id]
            post_request("/api/v1/Recorders('#{self[:device_id]}')/Stop")
        end
    end
end
