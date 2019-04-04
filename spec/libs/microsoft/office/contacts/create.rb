# encoding: ASCII-8BIT
# frozen_string_literal: true

require 'rails'
require 'uv-rays'
require 'microsoft/office/client'


describe "office365 contact creation" do
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
        @mailbox = 'cam@acaprojects.com'
        @first_name = "Joe" 
        @last_name = "Smith"
        @email = 'joe@fakeemail.com'
        @organisation = "Company inc"
        @title = "Mr"
        @phone = "0404851331"
    end

    it "should create a contact with corresponding details" do
        @office = ::Microsoft::Officenew::Client.new(@office_credentials)
        contact = nil
        reactor.run {
            contact = @office.create_contact(mailbox: @mailbox, email: @email, first_name: @first_name, last_name: @last_name, options:{ title: @title, phone: @phone, organisation: @organisation })
        }
        expect(contact['email']).to eq(@email)
        reactor.run {
            @office.delete_contact(mailbox: @mailbox, contact_id: contact['id'])
        }
    end
end
