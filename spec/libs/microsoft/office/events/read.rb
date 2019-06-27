# encoding: ASCII-8BIT
# frozen_string_literal: true

require 'rails'
require 'uv-rays'
require 'microsoft/office/client'


describe "office365 event reading" do
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
        @mailbox = "cam@acaprojects.com"
        @start_time = Time.now
        @end_time = @start_time + 30.minutes
        @subject = "Test Booking #{(rand * 10000).to_i}"
        @body = "Test Body"
        @attendees = [{name: "Cram Creeves", email: "reeves.cameron@gmail.com"}, {name: "Cam Reeves", email: "cam@acaprojects.com"}]
        @extensions = { test_ext: 'NOT UPDATED' }
        @rooms = [{ email: 'testroom1@acaprojects.com', name: "Test Room" }]
        @booking_body = {
            mailbox: @mailbox,
            start_param: @start_time.to_i,
            end_param: @end_time.to_i,
            options: {
                rooms: @rooms,
                subject: @subject,
                description: @body,
                attendees: @attendees,
                extensions: @extensions
            }
        }
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        @booking = nil
        reactor.run {
            @booking = @office.create_booking(@booking_body)
        }
    end

    it 'should return events within the passed in time range INCLUSIVE of start and end time' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        bookings = nil
        reactor.run {
            bookings = @office.get_bookings(mailboxes: [ @mailbox ], options: { bookings_from: @start_time.to_i, bookings_to: @end_time.to_i })
        }
        expect(bookings.keys.map{|k| k.to_s.downcase }).to include(@mailbox.downcase)
        expect(bookings[@mailbox][:bookings].map{|b| b['subject'] }).to include(@subject)
        reactor.run {
            @office.delete_booking(mailbox: @booking['organizer'][:email], booking_id: @booking['id'])
        }
    end

    it 'should not return events outside the passed in time range' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        bookings = nil
        reactor.run {
            bookings = @office.get_bookings(mailboxes: [ @mailbox ], options: { bookings_from: (@start_time + 2.hours).to_i, bookings_to: (@end_time + 3.hours).to_i })
        }
        expect(bookings[@mailbox][:bookings].map{|b| b['subject'] }).not_to include(@subject)
        reactor.run {
            @office.delete_booking(mailbox: @booking['organizer'][:email], booking_id: @booking['id'])
        }
    end

    it 'should return the room as unavailable when checking availability in the time range' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        bookings = nil
        reactor.run {
            bookings = @office.get_bookings(mailboxes: [ @mailbox ], options: { available_from: @start_time.to_i, available_to: @end_time.to_i })
        }
        expect(bookings[@mailbox][:available]).to eq(false)
        reactor.run {
            @office.delete_booking(mailbox: @booking['organizer'][:email], booking_id: @booking['id'])
        }
    end

    it 'should return the room as available if the conflicting booking ID is passed to the ignore_bookings param' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        bookings = nil
        reactor.run {
            bookings = @office.get_bookings(mailboxes: [ @mailbox ], options: { available_from: @start_time.to_i, available_to: @end_time.to_i, ignore_bookings: [@booking['id']] })
        }
        expect(bookings[@mailbox][:available]).to eq(true)
        reactor.run {
            @office.delete_booking(mailbox: @booking['organizer'][:email], booking_id: @booking['id'])
        }
    end

    it 'should return events with their extension data at the root of the event' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        bookings = nil
        reactor.run {
            bookings = @office.get_bookings(mailboxes: [ @mailbox ], options: { bookings_from: @start_time.to_i, bookings_to: @end_time.to_i })
        }
        booking = bookings[@mailbox][:bookings].select{|b| b['subject'] == @subject}[0]
        @extensions.each do |ext_key, ext_value|
            expect(booking[ext_key.to_s]).to eq(ext_value)
        end
        reactor.run {
            @office.delete_booking(mailbox: @booking['organizer'][:email], booking_id: @booking['id'])
        }
    end


end
