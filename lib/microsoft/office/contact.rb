class Microsoft::Officenew::Contact < Microsoft::Officenew::Model

    ALIAS_FIELDS = {
        'id' => 'id',
        'title' => 'title',
        'mobilePhone' => 'phone',
        'displayName' => 'name',
        'personalNotes' => 'notes',
        'emailAddresses' => { 0 => { 'address' => 'email' } }
    }

    NEW_FIELDS = {}

    hash_to_reduced_array(ALIAS_FIELDS).each do |field|
        define_method field do
            @contact[field]
        end
    end

    def initialize(client:, contact:)
        @client = client
        @contact = create_aliases(contact, ALIAS_FIELDS, NEW_FIELDS, self)
    end

    attr_accessor :contact
end
