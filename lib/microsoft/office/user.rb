class Microsoft::Officenew::User < Microsoft::Officenew::Model

    ALIAS_FIELDS = {
        'id' => 'id',
        'mobilePhone' => 'phone',
        'displayName' => 'name',
        'mail' => 'email',
        'jobTitle' => 'role'
    }

    NEW_FIELDS = {}

    hash_to_reduced_array(ALIAS_FIELDS).each do |field|
        define_method field do
            @user[field]
        end
    end

    def initialize(client:, user:)
        @client = client
        @user = create_aliases(user, ALIAS_FIELDS, NEW_FIELDS, self)
    end

    def get_contacts
        @client.get_contacts(mailbox: @user['mail'])
    end

    def to_json(options)
        super(:only => :user)
    end


    attr_accessor :user
end