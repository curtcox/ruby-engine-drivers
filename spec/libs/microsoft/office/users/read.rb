# encoding: ASCII-8BIT
# frozen_string_literal: true

require 'rails'
require 'uv-rays'
require 'microsoft/office/client'


describe "office365 user reading" do
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
        @query = "ca"
        @email = "cam@acaprojects.com"
    end

    it 'should return all users with name or email matching query string' do
        @office = ::Microsoft::Office2::Client.new(@office_credentials)
        users = nil
        reactor.run {
            users = @office.get_users(q: @query)
        }
        users.each do |user|
            expect(user['name'].downcase + user['email'].downcase).to include(@query)
        end
    end

    it 'should return one user if an email is passed' do
        @office = ::Microsoft::Office2::Client.new(@office_credentials)
        users = nil
        reactor.run {
            users = @office.get_users(q: @email)
        }
        expect(users.length).to eq(1)
        expect(users[0]['email'].downcase).to eq(@email)
    end

end
