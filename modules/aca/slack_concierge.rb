require 'slack-ruby-client'
require 'slack/real_time/concurrency/libuv'

class Aca::Slack
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security


    descriptive_name 'Slack Concierge Connector'
    generic_name :Slack
    implements :logic

    def on_load
        create_websocket

        on_update
    end

    def on_update
        self[:building] = setting(:building) || :barangaroo
        self[:channel] = setting(:channel) || :concierge
    end

    # Message from the concierge frontend
    def send_message(message_text, thread_id)
        message = @client.web_client.chat_postMessage channel: setting(:channel), text: message_text, thread_ts: thread_id, username: 'Concierge'
    end

    def get_threads
        messages = @client.web_client.channels_history({channel: setting(:channel), count: 1000})['messages']
        messages.delete_if{ |message|
            !((!message.key?('thread_ts') || message['thread_ts'] == message['ts']) && message['subtype'] == 'bot_message')
        }
        self["threads"] = messages
    end

    def get_thread(thread_id)
        # Get the messages
        slack_api = UV::HttpEndpoint.new("https://slack.com")
        req = {
            token: @client.token,
            channel: setting(:channel),
            thread_ts: thread_id
        }
        response = slack_api.post(path: 'https://slack.com/api/channels.replies', body: req).value
        messages = JSON.parse(response.body)['messages']
        self["thread_#{thread_id}"] = messages
    end

    protected

    # Create a realtime WS connection to the Slack servers
    def create_websocket

        ::Slack.configure do |config|
            config.token = setting(:slack_api_token)
            config.logger = Logger.new(STDOUT)
            config.logger.level = Logger::INFO
            fail 'Missing slack api token setting!' unless config.token
        end
        ::Slack::RealTime.configure do |config|
            config.concurrency = Slack::RealTime::Concurrency::Libuv
        end

        @client = ::Slack::RealTime::Client.new

        logger.debug "Created client!!"

        @client.on :message do |data|
            logger.debug "Got message!"
            begin
                #@client.typing channel: data.channel
                # Disregard if we have a subtype key and it's a reply to a message
                if data.key?('subtype') && data['subtype'] == 'message_replied'
                    next
                end
                get_threads
                if data.key?('thread_ts')
                    get_thread(data['thread_ts'])
                end
            rescue Exception => e
                logger.debug e.message
                logger.debug e.backtrace
            end
        end

    @client.start!

    end
end
