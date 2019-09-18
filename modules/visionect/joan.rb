# frozen_string_literal: true

module Visionect; end

class Visionect::Joan
    include ::Orchestrator::Constants

    # Metadata for discovery
    descriptive_name 'Joan'
    generic_name :LowPowerDisplayPanel
    description 'Joan low power display panel'

    # If the driver points to a static API endpoint that is likely to be the
    # same across all instances, you can define that here.
    uri_base 'https://api.visionect.com/'
    # Alertnatively, to force the base URI to be entered per instance the above
    # can be ommitted in place of...
    # implements :service

    def on_update
        # Setting have been changed - if you are using these to define an API
        # key, it's a good idea to validate it here.
    end

    # Example public method - this will be exposed as part of the API and
    # available as an 'exec' request to all authenticated users.
    #
    # See https://developer.acaprojects.com/#/driver-development/logging-and-security?id=security
    # for information on restricting access.
    def roundhouse_me
        logger.debug 'One Chuck Norris '

        # Perform an asynconous HTTP request
        get('/jokes/random', query: { category: 'dev' }) do |data|

            # Handle the response (when we get it)
            parse(data) do |response|
                # Push some information into the exposed module state. This
                # is available for client to 'bind' to
                self[:last_fact] = response[:value]
            end

        end
    end

    def display(url)
        logger.debug "Setting panel to #{url}"

        # Perform an asynconous HTTP request
        get('/jokes/random', query: { category: 'dev' }) do |data|

            # Handle the response (when we get it)
            parse(data) do |response|
                # Push some information into the exposed module state. This
                # is available for client to 'bind' to
                self[:last_fact] = response[:value]
            end

        end
    end

    def reboot
        uuid = '47001e00-0150-4d35-5232-312000000000'
        logger.debug "Rebooting device"

        # Perform an asynconous HTTP request
        response = post("/api/device/#{uuid}/reboot", headers: {Authorization: 'value'}) do |data|
            logger.debug "Rebooting device"

            # Handle the response (when we get it)
            parse(data) do |response|
              logger.debug "Parsed OK"
            end

        end
        response.then {logger.debug "Success"}
                .catch {logger.error "Error"}
    end

    protected

    # Example protected method - not exposed to the outside world.
    def parse(data)
        case data.status
        when 200
            begin
                yield JSON.parse data.body, symbolize_names: true
                :success
            rescue JSON::ParserError
                logger.error 'Chuck Norris does not make errors - please update the JSON spec to conform'
                :above
            end
        else
            logger.error { "unexpected response code in #{data}" }
            :abort
        end
    end
end
