class Microsoft::Office2::Model

    def create_aliases(object, alias_fields, new_fields, model)
        aliased_contact = object.each_with_object({}) do |(k,v), h|
            if alias_fields.keys.include?(k)
                new_field = alias_reduction(k, alias_fields[k], v)
                h[new_field[:key]] = new_field[:value]
            end
        end
        new_fields.each do |field|
            aliased_contact[field[:new_key]] = model.__send__(
                field[:method],
                *((field[:model_params] || []).map{|p| object[p.to_s]}),
                *((field[:passed_params] || []).map{|p| self.__send__(p)
            }))
        end
        aliased_contact
    end

    # If the alias_field value is a string, then use the string, otherwise dig deeper using the hash
    def alias_reduction(alias_key, alias_value, object_value)
        # If it's a string, return it and use this as the new key
        return {key: alias_value, value: object_value} if alias_value.class == String
        new_alias_key = alias_value.keys[0]
        new_alias_key
        alias_reduction(new_alias_key, alias_value[new_alias_key], object_value[new_alias_key])
    end

    # This method takes a hash which has either strings as values or hashes that can be reduced to strings
    def self.hash_to_reduced_array(hash_object)
        reduced = []
        hash_object.each do |k,v|
            reduced.push(reduce_hash(v))
        end
        reduced
    end

    def self.reduce_hash(value)
        return value if value.class == String
        reduce_hash(value[value.keys[0]])
    end

end
