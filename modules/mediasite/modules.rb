# frozen_string_literal: true

require 'net/http'

module Mediasite; end

class Mediasite::Module
    descriptive_name 'Mediasite'
    generic_name :Recorder
    implements :logic

    default_settings({
        url: 'https://alex-dev.deakin.edu.au/Mediasite/',
        username: 'acaprojects',
        password: 'WtjtvB439cXdZ4Z3'
    })

    def on_load

        on_update
    end

    def on_update
        uri = URI.parse(setting(:url))
        request = Net::HTTP::GET.new(URI.parse(uri))
        request.basic_auth(setting(:username), setting(:password))
        http = Net::HTTP.new(uri.host, uri.port)
        response = http.request(request)
    end
end
