# frozen_string_literal: true

require 'net/http'

module Mediasite; end

class Mediasite::Module
  descriptive_name 'Mediasite'
  generic_name :Recorder
  implements :logic

  def on_load
       on_update
   end

   def on_update
=begin
       ret = Net::HTTP.get(URI.parse('https://www.meethue.com/api/nupnp'))
       parsed = JSON.parse(ret) # parse the JSON string into a usable hash table
       ip_address = parsed[0]['internalipaddress']
       @url = "http://#{ip_address}/api/#{setting(:api_key)}/sensors/7"
       logger.debug { "url is #{@url}" }
=end
   end

end
