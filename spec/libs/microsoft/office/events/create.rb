# encoding: ASCII-8BIT
# frozen_string_literal: true

require 'rails'
require 'uv-rays'
require 'microsoft/office/client'


describe "office365 events" do
    before :each do
        @office_credentials = {
            client_id: ENV['OFFICE_CLIENT_ID'],
            client_secret: ENV["OFFICE_CLIENT_SECRET"],
            app_site: ENV["OFFICE_SITE"] || "https://login.microsoftonline.com",
            app_token_url: ENV["OFFICE_TOKEN_URL"],
            app_scope: ENV['OFFICE_SCOPE'] || "https://graph.microsoft.com/.default",
            graph_domain: ENV['GRAPH_DOMAIN'] || "https://graph.microsoft.com",
            save_token: Proc.new{ |token| @token = token },
            get_token: Proc.new{ nil }
        }
        @start_time = Time.now
        @end_time = @start_time + 30.minutes
        @title = "Test Booking"
        @body = "Test Body"
        @attendees = [{name: "Cram Creeves", email: "reeves.cameron@gmail.com"}, {name: "Cam Reeves", email: "cam@acaprojects.com"}]
        @extensions = { test_ext: 123 }
        @rooms = [{ email: 'testroom1@acaprojects.com', name: "Test Room" }]
        @booking_body = {
            mailbox: "cam@acaprojects.com",
            start_param: @start_time.to_i,
            end_param: @end_time.to_i,
            options: {
                rooms: @rooms,
                subject: @title,
                description: @body,
                attendees: @attendees,
                extensions: @extensions
            }
        }
    end

    it "should initialize with client application details" do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        expect(@office).not_to be_nil
    end

    it 'should create events in o365 at the passed in time' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        booking = nil
        reactor.run {
            booking = @office.create_booking(@booking_body)
        }
        expect(booking['start_epoch']).to eq(@start_time.to_i)
        reactor.run {
            @office.delete_booking(mailbox: booking['organizer'][:email], booking_id: booking['id'])
        }
    end

    it 'should create events in o365 with the passed in attendees' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        booking = nil
        reactor.run {
            booking = @office.create_booking(@booking_body)
        }
        booking['attendees'].each do |attendee|
            expect(@attendees.map{ |a| a[:email] }).to include(attendee[:email])    
        end
        
        reactor.run {
            @office.delete_booking(mailbox: booking['organizer'][:email], booking_id: booking['id'])
        }
    end

    it 'should create events in o365 containing the passed in rooms' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        booking = nil
        reactor.run {
            booking = @office.create_booking(@booking_body)
        }
        expect(booking['room_emails'].map{ |e| e.downcase }.sort).to eq(@rooms.map{|r| r[:email].downcase}.sort)    
        
        reactor.run {
            @office.delete_booking(mailbox: booking['organizer'][:email], booking_id: booking['id'])
        }
    end

    it 'should create events in o365 with the passed in title' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        booking = nil
        reactor.run {
            booking = @office.create_booking(@booking_body)
        }
        expect(booking['subject']).to eq(@title)
        
        reactor.run {
            @office.delete_booking(mailbox: booking['organizer'][:email], booking_id: booking['id'])
        }
    end

    it 'should create events in o365 with the body as the passed in description' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        booking = nil
        reactor.run {
            booking = @office.create_booking(@booking_body)
        }
        expect(booking['body']).to include(@body)
        
        reactor.run {
            @office.delete_booking(mailbox: booking['organizer'][:email], booking_id: booking['id'])
        }
    end

    it 'should create events in o365 with any passed in extensions at the root of the event' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        booking = nil
        reactor.run {
            booking = @office.create_booking(@booking_body)
        }
        @extensions.each do |ext_key, ext_value|
            expect(booking[ext_key.to_s]).to eq(ext_value)
        end
        
        reactor.run {
            @office.delete_booking(mailbox: booking['organizer'][:email], booking_id: booking['id'])
        }
    end

end
