# encoding: ASCII-8BIT
# frozen_string_literal: true

=begin

Example Usage:
bw = Cisco::BroadSoft::BroadWorks.new("xsi-events.domain.com", "user@domain.com", "Password!", proxy: ENV['HTTPS_PROXY'])

# Processing events
Thread.new do
  bw.open_channel do |event|
    thread.new { bw.acknowledge(event[:event_id]) }
    puts "\n\Processing! #{event}\n\n"
  end
end

# Keeping the connection alive
Thread.new do
  sleep 8
  loop do
    bw.heartbeat
    sleep 5
  end
end

# Registering for Automatic Call Distribution Events
bw.get_user_events "0478242466@domain.au"

=end

require "active_support/all"
require "securerandom"
require "nokogiri"
require "logger"
require "httpi"
require "json"

module Cisco; end
module Cisco::BroadSoft; end

class Cisco::BroadSoft::BroadWorks
  def initialize(domain, username, password, application: "ACAEngine", proxy: nil, logger: Logger.new(STDOUT))
    @domain = domain
    @username = username
    @password = password
    @logger = logger
    @proxy = proxy
    @application_id = application

    @channel_set_id = SecureRandom.uuid
  end

  attr_reader :expires
  attr_reader :channel_id
  attr_reader :channel_set_id

  def open_channel
    expires = 6.hours.to_i

    channel_xml = %(<?xml version="1.0" encoding="utf-8"?>
    <Channel xmlns="http://schema.broadsoft.com/xsi">
      <channelSetId>#{@channel_set_id}</channelSetId>
      <priority>1</priority>
      <weight>50</weight>
      <expires>#{expires}</expires>
    </Channel>)

    conn = new_request
    conn.url = "https://#{@domain}/com.broadsoft.async/com.broadsoft.xsi-events/v2.0/channel"
    conn.body = channel_xml

    conn.on_body do |chunk|
      event = parse_event(chunk)
      yield event if event
    end

    @logger.info "Channel #{@channel_set_id} requested..."
    HTTPI.post(conn)
    @logger.info "Channel #{@channel_set_id} closed..."
  end

  def heartbeat
    conn = new_request
    conn.url = "https://#{@domain}/com.broadsoft.xsi-events/v2.0/channel/#{@channel_id}/heartbeat"
    response = HTTPI.put(conn)
    if response.code != 200
      @logger.warn "heartbeat failed\n#{response.inspect}"
    end
  end

  def acknowledge(event_id)
    channel_xml = %(<?xml version="1.0" encoding="utf-8"?>
    <EventResponse xmlns="http://schema.broadsoft.com/xsi">
      <eventID>#{event_id}</eventID>
      <statusCode>200</statusCode>
      <reason>OK</reason>
    </EventResponse>)

    conn = new_request
    conn.url = "https://#{@domain}/com.broadsoft.xsi-events/v2.0/channel/eventresponse"
    conn.body = channel_xml
    response = HTTPI.post(conn)
    if response.code == 200
      @logger.debug "acknowledgment #{event_id}"
    else
      @logger.warn "acknowledgment failed\n#{response.inspect}"
    end
  end

  def parse_event(data)
    xml = Nokogiri::XML(data)
    xml.remove_namespaces!

    begin
      response_type = xml.children[0].name
      case response_type
      when 'Channel'
        @channel_id = xml.xpath("//channelId").inner_text
        @expires = (xml.xpath("//expires").inner_text.to_i - 5).seconds.from_now
        @logger.info "channel established #{@channel_id}"
        @logger.debug "channel details:\n#{data}"
        nil
      when 'Event'
        event_data = xml.xpath("//eventData")[0]
        {
          event_id: xml.xpath("//eventID").inner_text,
          event_name: event_data["type"].split(':')[1],
          event_data: event_data
        }
      else
        @logger.info "recieved #{response_type} on channel"
        nil
      end
    rescue => e
      @logger.error "processing event\n#{e.message}\nevent: #{data}"
      nil
    end
  end

  # Admin Commands:
  def renew(expires_in = 6.hours.to_i)
    channel_xml = %(<?xml version="1.0" encoding="utf-8"?>
    <Channel xmlns="http://schema.broadsoft.com/xsi">
      <expires>#{expires_in}</expires>
    </Channel>)

    conn = new_request
    conn.url = "https://#{@domain}/com.broadsoft.xsi-events/v2.0/channel/#{@channel_id}"
    conn.body = channel_xml
    response = HTTPI.put(conn)
    if response.code != 200
      @logger.warn "channel renewal failed\n#{response.inspect}"
    end
  end

  def close_channel
    conn = new_request
    conn.url = "https://#{@domain}/com.broadsoft.xsi-events/v2.0/channel/#{@channel_id}"
    response = HTTPI.delete(conn)
    if response.code != 200
      @logger.warn "channel close failed\n#{response.inspect}"
    end
  end

  def get_user_events(group, events = "Call Center Queue")
    channel_xml = %(<?xml version="1.0" encoding="UTF-8"?>
      <Subscription xmlns="http://schema.broadsoft.com/xsi">
        <event>#{events}</event>
        <expires>#{6.hours.to_i}</expires>
        <channelSetId>#{@channel_set_id}</channelSetId>
        <applicationId>#{@application_id}</applicationId>
      </Subscription>)

    conn = new_request
    conn.url = "https://#{@domain}/com.broadsoft.xsi-events/v2.0/user/#{group}"
    conn.body = channel_xml
    response = HTTPI.post(conn)
    if response.code == 200
      # TODO:: extract the subscription ID
    else
      @logger.warn "get user events failed\n#{response.inspect}"
    end
  end

  def new_request
    conn = HTTPI::Request.new
    conn.proxy = @proxy if @proxy
    conn.headers['Content-Type'] = 'application/xml'
    conn.headers['Accept'] = 'application/xml; charset=UTF-8'
    conn.auth.basic(@username, @password)
    conn
  end
end
