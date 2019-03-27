# frozen_string_literal: true
# encoding: ASCII-8BIT

module Cisco; end

::Orchestrator::DependencyManager.load('Cisco::BroadSoft::BroadWorks', :model, :force)

class Cisco::BroadWorks
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security

    descriptive_name 'Cisco BroadWorks Call Center Management'
    generic_name :CallCenter

    # Discovery Information
    implements :service
    keepalive false # HTTP keepalive

    default_settings({
        username: :cisco,
        password: :cisco,
        events_domain: 'xsi-events.endpoint.com',
        proxy: 'http://proxy.com:8080',
        callcenters: {"phone_number@domain.com" => "Other Matters"}
    })

    def on_load
        HTTPI.log = false
        @terminated = false

        # TODO:: Load todays stats from the database if they exist


        on_update
    end

    def on_update
        @username = setting(:username)
        @password = setting(:password)
        @domain = setting(:events_domain)
        @proxy = setting(:proxy) || ENV["HTTPS_PROXY"] || ENV["https_proxy"]
        @callcenters = setting(:callcenters) || {}

        # "sub_id" => "callcenter id"
        @subscription_lookup = {}

        @poll_sched&.cancel
        @reset_sched&.cancel

        # Every 2 min
        @poll_sched = schedule.every(120_000) do
            @callcenters.each_key { |id| get_call_count(id) }
        end
        # Every day at 5am
        @reset_sched = schedule.cron("0 5 * * *") { reset_stats }

        connect
    end

    def reset_stats
        # "callcenter id" => count
        @queued_calls = {}
        @abandoned_calls = {}

        # "callcenter id" => Array(wait_times)
        @calls_taken = {}
    end

    def on_unload
        @terminated = true
        @bw.close_channel
    end

    def connect
        return if @terminated

        @bw.close_channel if @bw
        reactor = self.thread
        callcenters = @callcenters

        @bw = Cisco::BroadSoft::BroadWorks.new(@domain, @username, @password, proxy: @proxy)
        bw = @bw
        Thread.new do
            bw.open_channel do |event|
                reactor.schedule { process_event(event) }
            end
        end
        nil
    end

    SHOULD_UPDATE = Set.new(['ACDCallAddedEvent', 'ACDCallAbandonedEvent', 'CallReleasedEvent', 'ACDCallStrandedEvent', 'ACDCallAnsweredByAgentEvent'])

    def process_event(event)
        # Check if the connection was terminated
        if event.nil?
            if !@terminated
                schedule.in(1000) do
                    @bw = nil
                    connect
                end
            end
            return
        end

        # Lookup the callcenter in question
        call_center_id = @subscription_lookup[event[:subscription_id]]

        # Otherwise process the event
        case event[:event_name]
        when 'new_channel'
            monitor_callcenters
        when 'ACDCallAddedEvent'
            count = @queued_calls[call_center_id]
            @queued_calls[call_center_id] = count.to_i + 1
        when 'ACDCallAbandonedEvent'
            count = @abandoned_calls[call_center_id]
            @abandoned_calls[call_center_id] = count.to_i + 1

            count = @queued_calls[call_center_id]
            @queued_calls[call_center_id] = count.to_i - 1
        when 'CallReleasedEvent', 'ACDCallStrandedEvent'
            # Not entirely sure when this happens
            count = @queued_calls[call_center_id]
            @queued_calls[call_center_id] = count.to_i - 1
        when 'ACDCallAnsweredByAgentEvent'
            # TODO:: Call answered by "0278143573@det.nsw.edu.au"
            # Possibly we can monitor the time this conversion goes for?
            count = @queued_calls[call_center_id]
            @queued_calls[call_center_id] = count.to_i - 1

            # Extract wait time...
            event_data = event[:event_data]
            start_time = event_data.xpath("//addTime").inner_text.to_i
            answered_time = event_data.xpath("//removeTime").inner_text.to_i
            wait_time = answered_time - start_time

            wait_times = @calls_taken[call_center_id] || []
            wait_times << wait_time
            @calls_taken[call_center_id] = wait_times
        else
            logger.debug { "ignoring event #{event[:event_name]}" }
        end

        if SHOULD_UPDATE.include?(event[:event_name])
            update_stats
        end
    end

    def monitor_callcenters
        # Reset the lookups
        @subscription_lookup = {}
        @queued_calls = {}

        bw = @bw
        reactor = self.thread
        @callcenters.each do |id, name|
            # Run the request on the thread pool
            retries = 0
            begin
                task {
                    sub_id = bw.get_user_events(id)

                    # Ensure the mapping is maintained
                    reactor.schedule do
                        if bw.channel_open
                            @subscription_lookup[sub_id] = id
                            get_call_count(id)
                        end
                    end
                }.value

                break unless bw.channel_open
            rescue => e
                logger.error "monitoring callcenter #{name}\n#{e.message}"
                break unless bw.channel_open
                retries += 1
                retry unless retries > 3
            end
        end
    end

    # Non-event related calls
    def get_call_count(call_center_id)
        get('/com.broadsoft.xsi-actions/v2.0/callcenter/#{call_center_id}/calls') do |data, resolve, command|
            if data.status == 200
                xml = Nokogiri::XML(data.body)
                xml.remove_namespaces!
                @queued_calls[call_center_id] = xml.xpath("//queueEntry").length
            else
                logger.warn "failed to retrieve active calls for #{@callcenters[call_center_id]} - response code: #{data&.status}"
            end
            :success
        end
    end

    def update_stats
        queues = {}
    end
end
