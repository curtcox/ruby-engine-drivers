module MessageMedia; end

# Documentation: https://developers.messagemedia.com/code/messages-api-documentation/

class MessageMedia::SMS
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder

    # Discovery Information
    implements :service
    descriptive_name 'Pexip Management API'
    generic_name :Pexip

    # HTTP keepalive
    keepalive false

    def on_load
        on_update
    end

    def on_update
        # NOTE:: base URI https://api.messagemedia.com
        @username = setting(:username)
        @password = setting(:password)
        proxy = setting(:proxy)
        if proxy
            config({
                proxy: {
                    host: proxy[:host],
                    port: proxy[:port]
                }
            })
        end
    end

    def sms(text, numbers, source = nil)
        text = text.to_s
        numbers = Array(numbers).map do |number|
            message = {
                content: text,
                destination_number: number.to_s,
                format: 'SMS'
            }
            if source
                message[:source_number] = source.to_s
                message[:source_number_type] = "ALPHANUMERIC"
            end
            message
        end

        post('/v1/messages', body: {
            messages: numbers
        }.to_json, headers: {
            'Authorization' => [@username, @password],
            'Content-Type' => 'application/json',
            'Accept' => 'application/json'
        })
    end

    def received(data, resolve, command)
        if data.status == 202
            :success
        else
            :retry
        end
    end
end
