require 'net/http'
require 'rubygems'
require 'json'
require 'uv-rays'
require 'libuv'
require 'microsoft/exchange'

module Philips; end

class Philips::Hue
    include ::Orchestrator::Constants

    descriptive_name 'Philips Hue Motion Sensor'
    generic_name :Sensor
    implements :logic

    default_settings({
        api_key: 'RKIKef3WgZIQk9FUlMZ2qPqrrwAaTIV3mzetNI2I',
        threshold: 10, # number of seconds for testing, number of minutes for real life
        minimum_booking_duration: 1 # in minutes
    })

    def on_load
        on_update
    end

    def on_update
        stop
        ret = Net::HTTP.get(URI.parse('https://www.meethue.com/api/nupnp'))
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table
        ip_address = parsed[0]['internalipaddress']
        @url = "http://#{ip_address}/api/#{setting(:api_key)}/sensors/7"
        logger.debug { "url is #{@url}" }
        @ews = ::Microsoft::Exchange.new({
            ews_url: 'https://outlook.office365.com/ews/Exchange.asmx',
            service_account_email: 'cam@acaprojects.com',
            service_account_password: 'Aca1783808'
        })
    end

    # Every x amount of time, check if presence is true
    def booking_has_presence(booking)
        start_time = DateTime.parse(Time.at(booking[:start_date].to_i / 1000).to_s)
        end_time = DateTime.parse(Time.at(booking[:end_date].to_i / 1000).to_s)
        logger.debug {
            "Creating a scheduled task for #{booking[:title]} starting at #{start_time} and ending at #{end_time}"
        }
        @scheduled_bookings[booking[:title]] = schedule.at(@ews.ensure_ruby_date(start_time)) do
            logger.debug { "Starting check for #{booking[:title]}" }
            Thread.new do
                noshow = false
                analytics = 0
                # can schedule a check here to make sure the booking is still valid
                ::Libuv::Reactor.new.run do |reactor|
                    ref = reactor.scheduler.every('5s') do
                        if DateTime.now <= start_time + setting(:threshold).seconds
                            if has_presence
                                analytics = 1
                                ref.cancel
                            else
                                logger.debug { "Waiting for booking to show up" }
                            end
                        # check for this condition first incase of booking duration < threshold
                        elsif DateTime.now > end_time
                            analytics = 2
                            ref.cancel
                        elsif DateTime.now > start_time + setting(:threshold).seconds
                            # cancel the booking since its after the threshold
                            logger.debug { "Cancelled booking, waiting for walk-in" }

                            if !noshow
                                noshow = true # set the noshow flag so this only happens once
                                #@ews.cancel_booking
                            end

                            if has_presence
                                ref.cancel
                                create_walkin_booking
                                analytics = 3
                            end
                        end
                    end
                end

                logger.debug { "Analytics is #{analytics}" }
                case analytics
                when 0
                    logger.debug { "Error" }
                when 1
                    logger.debug { "Original booking showed up" }
                when 2
                    logger.debug { "No show and no walkin" }
                when 3
                    logger.debug { "Walkin" }
                end

                @scheduled_bookings.delete(booking[:title])
            end
        end
    end

    # Return true when detected and false when not
    def has_presence
        ret = Net::HTTP.get(URI.parse(@url)) # get sensor information in JSON format from api
        parsed = JSON.parse(ret) # parse the JSON string into a usable hash table
        presence = parsed['state']['presence']
    end

    def current_booking
        logger.debug { "Checking for new bookings" }
        @bookings = get_bookings
        if @bookings.length > 0 && !(@scheduled_bookings.include?(@bookings[0][:title]))
            booking_has_presence(@bookings[0])
        end
    end

    # Get a list of bookings
    def get_bookings
        curr = []
        today = DateTime.now.to_date

        @ews.get_bookings(email: "cam@acaprojects.com", use_act_as: true).each { |e|
            start_date = DateTime.parse(Time.at(e[:start_date].to_i / 1000).to_s)
            start_day = start_date.to_date

            if start_day.to_s == today.to_s # these are today's events
                if start_date > DateTime.now # show only future events
                    curr.push(e)
                end
            end
        }
        return curr
    end

=begin
    Creates a walkin booking ensuring it does not overlap with the next booking
    Default duration for walk in bookings has been set to 30 minutes
    If next booking is within 30 minutes, walk in booking end time will be set to 1 minute before the next booking's start time
=end
    def create_walkin_booking
        @bookings = get_bookings

        end_time = DateTime.now + setting(:minimum_booking_duration).minutes
        if(@bookings.length > 0)
            start_date = DateTime.parse(Time.at(@bookings[0][:start_date].to_i / 1000).to_s)
            logger.debug { "Next booking #{@bookings[0][:title]} starts at #{start_date}" }
            if end_time > start_date
                end_time = start_date - 1.minutes
            end
        end
=begin
        @ews.create_booking({
            room_email: "cam@acaprojects.com",
            start_param: DateTime.now,
            end_param: end_time,
            subject: "Walkin",
            current_user: #TODO
        })
=end
        logger.debug { "Creating a booking starting at #{DateTime.now} and ending at #{end_time}" }
    end

    # check for all bookings now and schedule the check for every future 7am
    def start
        current_booking

        schedule.every("#{setting(:minimum_booking_duration)}m") do
            current_booking
        end
    end

    def stop
        schedule.clear
        @scheduled_bookings = {}
        logger.debug { "Cleared schedule" }
    end

    def send_email

    end
end
