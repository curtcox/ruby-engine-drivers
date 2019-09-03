# encoding: ASCII-8BIT
# frozen_string_literal: true

require 'rails'
require 'uv-rays'
require 'microsoft/office/client'


describe "office365 event updating" do
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
        @subject = "Test Booking"
        @body = "Test Body"
        @attendees = [{name: "Cram Creeves", email: "reeves.cameron@gmail.com"}, {name: "Cam Reeves", email: "cam@acaprojects.com"}]
        @extensions = { test_ext: 'NOT UPDATED' }
        @rooms = [{ email: 'testroom1@acaprojects.com', name: "Test Room" }]
        @booking_body = {
            mailbox: "cam@acaprojects.com",
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
        @office = ::Microsoft::Office2::Client.new(@office_credentials)
        @booking = nil
        reactor.run {
            @booking = @office.create_booking(@booking_body)
        }

        puts "--------------------- Original booking ---------------------"
        puts @booking
        puts "--------------------"
        @new_start_time = Time.now + 1.day
        @new_end_time = @new_start_time + 30.minutes
        @new_subject = "Updated Test Booking"
        @new_body = "Updated Test Body"
        @new_attendees = [{name: "Atomic Creeves", email: "atomic778@gmail.com"}]
        @new_extensions = { updated_test_ext: 'UPDATED' }
        @new_rooms = [{ email: 'testroom2@acaprojects.com', name: "New Room" }]
        @update_body = {
            booking_id: @booking['id'],
            mailbox: "cam@acaprojects.com",
            options: {
                start_param: @new_start_time.to_i,
                end_param: @new_end_time.to_i,
                rooms: @new_rooms,
                subject: @new_subject,
                description: @new_body,
                attendees: @new_attendees,
                extensions: @new_extensions
            }
        }
    end

    it 'should return updated events with the passed in time' do
        @office = ::Microsoft::Office2::Client.new(@office_credentials)
        updated_booking = nil
        reactor.run {
            updated_booking = @office.update_booking(@update_body)
        }
        expect(updated_booking['start_epoch']).to eq(@new_start_time.to_i)
        reactor.run {
            @office.delete_booking(mailbox: updated_booking['organizer'][:email], booking_id: updated_booking['id'])
        }
    end

    it 'should return updated events with the passed in attendees' do
        @office = ::Microsoft::Office2::Client.new(@office_credentials)
        updated_booking = nil
        reactor.run {
            updated_booking = @office.update_booking(@update_body)
        }
        updated_booking['attendees'].each do |attendee|
            expect(@new_attendees.map{ |a| a[:email] }).to include(attendee[:email])    
        end
        reactor.run {
            @office.delete_booking(mailbox: updated_booking['organizer'][:email], booking_id: updated_booking['id'])
        }
    end
    it 'should return updated events with the passed in subject' do
        @office = ::Microsoft::Office2::Client.new(@office_credentials)
        updated_booking = nil
        reactor.run {
            updated_booking = @office.update_booking(@update_body)
        }

        expect(updated_booking['subject']).to eq(@new_subject)    

        reactor.run {
            @office.delete_booking(mailbox: updated_booking['organizer'][:email], booking_id: updated_booking['id'])
        }
    end

    it 'should return updated events with the passed in time' do
        @office = ::Microsoft::Office2::Client.new(@office_credentials)
        updated_booking = nil
        reactor.run {
            updated_booking = @office.update_booking(@update_body)
        }
        @new_extensions.each do |ext_key, ext_value|
            expect(updated_booking[ext_key.to_s]).to eq(ext_value)
        end
        reactor.run {
            @office.delete_booking(mailbox: updated_booking['organizer'][:email], booking_id: updated_booking['id'])
        }
    end
end
