# frozen_string_literal: true
# encoding: ASCII-8BIT

require 'protocols/snmp'
require 'aca/trap_dispatcher'

module Kentix; end

# Documentation: https://aca.im/driver_docs/Kentix/Kentix-KMS-LAN-API-1_0.pdf
# https://aca.im/driver_docs/Kentix/kentixdevices.mib

class Kentix::MultiSensor
    include ::Orchestrator::Constants

    descriptive_name 'Kentix MultiSensor'
    generic_name :Sensor
    implements :service

    default_settings communication_key: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',

    def on_load
        on_update
    end

    def on_update
        # default is a hash of an empty string
        @key = setting(:communication_key) || 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    end

    def connected
        schedule.clear
        schedule.every('10s', true) do
            get_state
        end
    end

    def get_state
        post('/api/1.0/', body: {
            command: 2200,
            type: :get,
            auth: @key,
            version: '1.0'
        }.to_json, headers: {
            'Content-Type' => 'application/json'
        }, name: :state) do |response|
            if response.status == 200
                data = ::JSON.parse(response.body, symbolize_names: true)
                if data[:error]
                    logger.debug { "error response\n#{data}" }
                    :abort
                else
                    self[:last_updated] = data[:timestamp]
                    data[:data][:system][:device].each do |key, value|
                        self[key] = value
                    end
                    :success
                end
            else
                :abort
            end
        end
    end
end
