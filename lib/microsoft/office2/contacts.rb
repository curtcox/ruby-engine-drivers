module Microsoft::Office2::Contacts
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
        JSON.parse(request.body)['value'].map {|c| Microsoft::Office2::Contact.new(client: self, contact: c).contact}
    end

    ##
    # Add a new contact to the passed in mailbox.
    # 
    # @param mailbox [String] The mailbox email to which we will save the new contact
    # @param email [String] The email of the new contact
    # @param first_name [String] The first name of the new contact
    # @param last_name [String] The last name of the new contact
    # @option options [String] :phone The phone number of the new contact
    # @option options [String] :organisation The organisation of the new contact
    # @option options [String] :title The title of the new contact
    def create_contact(mailbox:, email:, first_name:, last_name:, options:{})
        default_options = {
            phone: nil,
            organisation: nil,
            title: nil,
            other: {}
        }
        # Merge in our default options with those passed in
        options = options.reverse_merge(default_options)

        # This data is required so add it unconditionally
        contact_data = {
            givenName: first_name,
            surname: last_name,
            emailAddresses: [{
                address: email,
                name: "#{first_name} #{last_name}"
            }]
        }

        # Only add these fields if passed in
        contact_data[:title] = options[:title] if options[:title]
        contact_data[:businessPhones] = [ options[:phone] ] if options[:phone]
        contact_data[:companyName] = options[:organisation] if options[:organisation]

        # Add any fields that we haven't specified explicitly
        options[:other].each do |field, value|
            contact_data[field.to_sym] = value
        end

        # Make the request and return the result
        request = graph_request(request_method: 'post', endpoints: ["/v1.0/users/#{mailbox}/contacts"], data: contact_data)
        check_response(request)
        Microsoft::Office2::Contact.new(client: self, contact: JSON.parse(request.body)).contact
    end

    ##
    # Delete a new contact from the passed in mailbox.
    # 
    # @param mailbox [String] The mailbox email which contains the contact to delete
    # @param contact_id [String] The ID of the contact to be deleted
    def delete_contact(mailbox:, contact_id:)
        endpoint = "/v1.0/users/#{mailbox}/contacts/#{contact_id}"
        request = graph_request(request_method: 'delete', endpoints: [endpoint])
        check_response(request)
        200
    end

end