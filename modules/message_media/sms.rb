module MessageMedia; end

# Documentation: https://developers.messagemedia.com/code/messages-api-documentation/

class MessageMedia::SMS
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    implements :service
    descriptive_name 'MessageMedia SMS service'
    generic_name :SMS

    # HTTP keepalive
    keepalive false

    def on_load
        on_update
    end

    def on_update
        # NOTE:: base URI https://api.messagemedia.com
        @username = setting(:username)
        @password = setting(:password)
    end

    def sms(text, numbers)
        text = text.to_s
        numbers = Array(numbers).map do |number|
            {
                content: text,
                destination_number: number.to_s,
                format: 'SMS'
            }
        end

        post('/v1/messages', body: {
            messages: numbers
        }.to_json, headers: {
            'Authorization' => [@username, @password],
            'Content-Type' => 'application/json',
            'Accept' => 'application/json'
        })
    end
end
