require 'slack-ruby-client'
require 'slack/real_time/concurrency/libuv'
require 'microsoft/office'

# App ID: AG5KR5JSX
# Client ID: 32027075415.549671188915
# App Secret: 899130bef0277f54f17b7f8c49309c2d
# Signing Secret: 8e4f0421de528a602903aefc9acb4524
# Verification Token: eYEilNP8PpfLop3rjKmVE3gz
# Bot token: xoxb-32027075415-549994563445-ORN5cfzecXHfQsoa9qUD6WVM
class Aca::SlackBooking
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security


    descriptive_name 'Slack Booking'
    generic_name :Slack
    implements :logic

    def on_load
        on_update
    end

    def on_update
        on_unload   
        create_websocket
        self[:channel] = setting(:channel) || :concierge
    end

    def on_unload
        @client.stop! if @client && @client.started?
        @client = nil
    end
    
    # Message coming in from Slack API
    def on_message(data)
        matched_lines = [
            "free room",
            "free space",
            "available room",
        ]
        if matched_lines.include?(data['text'])
            @client.web_client.chat_postMessage channel: setting(:channel), text: "The following rooms are available:", username: 'Room Bot'
            rooms = Orchestrator::ControlSystem.all.to_a
            rooms.each do |room|
                if room.bookable && room.name.include?("SYD")
                    @client.web_client.chat_postMessage channel: setting(:channel), text: room.name, username: 'Room Bot'
                end
            end
        end
            # @office
    end

    protected

    # Create a realtime WS connection to the Slack servers
    def create_websocket


        @office = ::Microsoft::Office.new({
            client_id: ENV['OFFICE_CLIENT_ID'],
            client_secret: ( ENV["OFFICE_CLIENT_SECRET"] || "M6o]=6{Qi>*:?+_>|%}#_s[*/}$1}^N[.=D&>Lg--}!+{=&.*{/:|J_|%.{="),
            app_site: ENV["OFFICE_SITE"] || "https://login.microsoftonline.com",
            app_token_url: ENV["OFFICE_TOKEN_URL"],
            app_scope: ENV['OFFICE_SCOPE'] || "https://graph.microsoft.com/.default",
            graph_domain: ENV['GRAPH_DOMAIN'] || "https://graph.microsoft.com",
            service_account_email: ENV['OFFICE_ACCOUNT_EMAIL'],
            service_account_password: ENV['OFFICE_ACCOUNT_PASSWORD'],
            internet_proxy: ENV['INTERNET_PROXY']
        })

        # Set our token and other config options
        ::Slack.configure do |config|
            config.token = setting(:slack_api_token)
            config.logger = Logger.new(STDOUT)
            config.logger.level = Logger::INFO
            fail 'Missing slack api token setting!' unless config.token
        end

        # Use Libuv as our concurrency driver
	    ::Slack::RealTime.configure do |config|
	       config.concurrency = Slack::RealTime::Concurrency::Libuv
	    end

        # Create the client and set the callback function when a message is received
        @client = ::Slack::RealTime::Client.new
        @client.on :message do |data|
	    begin
            #@client.typing channel: data.channel
            on_message(data)
	    rescue Exception => e
	    end

        end
        # Start the client
	    @client.start!
    end

end
