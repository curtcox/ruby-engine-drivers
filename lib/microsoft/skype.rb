require 'active_support/time'
require 'logger'
module Microsoft
    class Error < StandardError
        class ResourceNotFound < Error; end
        class InvalidAuthenticationToken < Error; end
        class BadRequest < Error; end
        class ErrorInvalidIdMalformed < Error; end
        class ErrorAccessDenied < Error; end
    end
end

class Microsoft::Skype
    TIMEZONE_MAPPING = {
        "Sydney": "AUS Eastern Standard Time"
    }
    def initialize(
            domain:,
            client_id:,
            client_secret:,
            username:,
            password:
        )
        @domain = domain
        @username = username
        @password = password
        @client_id = client_id
        @client_secret = client_secret
    end 

    # Probably the only public method that will be called
    def create_meeting
        user_url = dicover_user_url
    end

    def get_token(url)
        uri = URI(url)
        resource = "#{uri.scheme}://#{uri.host}"
        token_uri = URI("https://login.windows.net/#{@domain.split('.').first}.onmicrosoft.com/oauth2/token")
        params = {:resource=>resource, :client_id=>@client_id, :grant_type=>"password",
                  :username=>@username, :password=>@password, :client_secret=>@client_secret}
        puts "PARAMS ARE"
        puts params
        skype_auth_api = UV::HttpEndpoint.new(token_uri, {inactivity_timeout: 25000, keepalive: false})
        request = skype_auth_api.post({path: token_uri, body: params, headers: {"Content-Type":"application/x-www-form-urlencoded"}})
        auth_response = nil
        reactor.run {
            auth_response = request.value
        }
        JSON.parse(auth_response.body)["access_token"]
    end

    def create_skype_meeting(subject)
        my_online_meetings_url = @app["_embedded"]["onlineMeetings"]["_links"]["myOnlineMeetings"]["href"]

        body = {accessLevel: "Everyone", subject: subject}

        url = @base_url+my_online_meetings_url
        r = RestClient.post url, body.to_json,  @apps_headers
        return JSON.parse(r.body)
    end

    def discover_user_url
        @skype_domain = "http://lyncdiscover.#{@domain}"
        skype_discover_api = UV::HttpEndpoint.new(@skype_domain, {inactivity_timeout: 25000, keepalive: false})
        discover_request = skype_discover_api.get
        discover_response = nil
        reactor.run {
            discover_response = discover_request.value
        }
        r = JSON.parse(discover_response.body)
        r["_links"]["user"]["href"]
    end

    def get_user_data        
        user_token = get_token(users_url)

        users_headers = {
            "Accept" => "application/json",
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{user_token}"
        }


        # GET to users_url
        skype_users_api = UV::HttpEndpoint.new(users_url, {inactivity_timeout: 25000, keepalive: false})
        user_request = skype_users_api.get({
            path: users_url,
            headers: users_headers
        })
        user_response = nil
        reactor.run {
            user_response = user_request.value
        }
        full_auth_response = JSON.parse(user_response.body)

    end

    def discover_apps_url(user_url)

    end
end
