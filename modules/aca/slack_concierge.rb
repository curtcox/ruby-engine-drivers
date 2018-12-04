require 'slack-ruby-client'
require 'slack/real_time/concurrency/libuv'

class Aca::SlackConcierge
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security


    descriptive_name 'Slack Concierge Connector'
    generic_name :Slack
    implements :logic

    def log(msg)
        logger.info msg
        STDERR.puts msg
        STDERR.flush
    end

    def on_load
        on_update
    end

    def on_update
        on_unload   
        create_websocket
        self[:building] = setting(:building) || :barangaroo
        self[:channel] = setting(:channel) || :concierge
    end

    def on_unload
        @client.stop! if @client && @client.started?
        @client = nil
    end

    # Message from the concierge frontend
    def send_message(message_text, thread_id)
        message = @client.web_client.chat_postMessage channel: setting(:channel), text: message_text, thread_ts: thread_id, username: 'Concierge'
    end

    def update_last_message_read(email_or_thread)
        authority_id = Authority.find_by_domain(ENV['EMAIL_DOMAIN']).id
        user = User.find_by_email(authority_id, email_or_thread)
        user = User.find(User.bucket.get("slack-user-#{email_or_thread}", quiet: true)) if user.nil?
        user.last_message_read = Time.now.to_i * 1000
        user.save!
    end


    def get_threads
        # Get the messages from far back (when over 1000 we need to paginate)
        page_count = 1
        all_messages = @client.web_client.channels_history({channel:setting(:channel), count: 1000})['messages']

        while (all_messages.length) == (1000 * page_count)
            page_count += 1
            all_messages += @client.web_client.channels_history({channel: "CEHDN0QP5", latest: all_messages.last['ts'], count: 1000})['messages']
        end

        # Delete messages that aren't threads ((either has no thread_ts OR thread_ts == ts) AND type == bot_message)
        messages = []
        all_messages.each do |message|
           messages.push(message) if (!message.key?('thread_ts') || message['thread_ts'] == message['ts']) && message['subtype'] == 'bot_message'
        end

        # Output count as if this gets > 1000 we need to paginate

        # For every message, grab the user's details out of it
        messages.each_with_index{|message, i|   
            # If the message has a username associated (not a status message, etc)
            # Then grab the details and put it into the message
            if message.key?('username')
                authority_id = Authority.find_by_domain(ENV['EMAIL_DOMAIN']).id
                user = User.find_by_email(authority_id, message['username'] )
                messages[i]['email'] = user.email
                messages[i]['name'] = user.name
            end

            # If the user sending the message exists (this should essentially always be the case)
            if !user.nil?
                messages[i]['last_sent'] = user.last_message_sent
                messages[i]['last_read'] = user.last_message_read
            else
                messages[i]['last_sent'] = nil
                messages[i]['last_read'] = nil
            end

            # update_last_message_read(messages[i]['email'])
            messages[i]['replies'] = get_message(message['ts'])
        }

        # Bind the frontend to the messages
        self["threads"] = messages
    end

    def get_message(thread_id)
        # Get the messages
        slack_api = UV::HttpEndpoint.new("https://slack.com")
        req = {
            token: @client.token,
            channel: setting(:channel),
            thread_ts: thread_id
        }
        response = slack_api.post(path: 'https://slack.com/api/channels.replies', body: req).value
        JSON.parse(response.body)['messages']
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
        return nil
    end


    protected

    # Create a realtime WS connection to the Slack servers
    def create_websocket

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
        
        get_threads


        @client.on :message do |data|

            begin

                # Ensure that it is a bot_message or slack client reply
                 if ['bot_message'].include?(data['subtype'])

                    # If this is a reply (has a thread_ts field)
                    if data.key?('thread_ts')
                        logger.info "!!!!! GOT INSIDE USING THREAD TS !!!!!"
                        logger.info "WITH TEXT #{data['text']}"

                        # Duplicate the current threads array so we don't have ref issues
                        new_threads = self["threads"].deep_dup

                        # Loop through the array and add user data
                        new_threads.each_with_index do |thread, i|
                            # If the ID of the looped message equals the new message thread ID
                            if thread['ts'] == data['thread_ts']
                                data['email'] = data['username']
                                new_threads[i]['replies'].insert(0, data.to_h.deep_dup)
                                break
                            end
                        end
                        self["threads"] = new_threads
                    else
                        logger.info "XXXXX GOT INSIDE WITHOUT THREAD TS XXXXX"
                        logger.info "WITH TEXT #{data['text']}"
                        replies_object = {
                            bot_id: data['bot_id'],
                            channel: data['channel'],
                            event_ts: data['event_ts'],
                            subtype: data['subtype'],
                            team: data['team'],
                            text: data['text'],
                            ts: data['ts'],
                            tester: "AHHH TEST",
                            type: data['type'],
                            username: data['username']
                        }
                        data['replies'] = [replies_object]
                        self["threads"] = self["threads"].to_h.deep_dup.insert(0, data.to_h.deep_dup)

                        if data['username'] != 'Concierge'
                            authority_id = Authority.find_by_domain(ENV['EMAIL_DOMAIN']).id
                            user = User.find_by_email(authority_id, data['username'])
                            if user
                                data['last_read'] = user.last_message_read
                                data['last_sent'] = user.last_message_sent
                            end
                        end
                    end    
                end                
                
            rescue Exception => e
            end
        end

        @client.start!

    end
end
