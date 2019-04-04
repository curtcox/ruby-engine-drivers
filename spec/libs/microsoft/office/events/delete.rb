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

    it 'should return 200 when an event is successfully deleted' do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        repsonse = nil
        reactor.run {
            repsonse = @office.delete_booking(mailbox: @mailbox, booking_id: @booking['id'])
        }
        expect(repsonse).to eq(200)
    end

end
