module Microsoft::Officenew::Contacts
    ##
    # Retrieve a list of contacts for some passed in mailbox
    # 
    # @param mailbox [String] The mailbox email of which we want to grab the contacts for
    # @param q [String] The query param which filters all contacts without a name or email matching this string
    # @param limit [String] The maximum number of contacts to return
    def get_contacts(mailbox:, q:nil, limit:nil)
        query_params = { '$top': (limit || 1000) }
        query_params['$filter'] = "startswith(displayName, '#{q}') or startswith(givenName, '#{q}') or startswith(surname, '#{q}') or emailAddresses/any(a:a/address eq  '#{q}')" if q
        endpoint = "/v1.0/users/#{mailbox}/contacts"
        request = graph_request(request_method: 'get', endpoints: [endpoint], query: query_params)
        check_response(request)
        JSON.parse(request.body)['value'].map {|c| Microsoft::Officenew::Contact.new(client: self, contact: c)}
    end
end