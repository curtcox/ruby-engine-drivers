# frozen_string_literal: true

module Cisco; end
module Cisco::Spark; end
module Cisco::Spark::Xapi; end

# Regexp's for tokenizing the xAPI command and response structure.
module Cisco::Spark::Xapi::Tokenize


    module_function

    # Split a space or slash seperated path into it's components.
    def path(xpath)
        if xpath.respond_to? :split
            xpath.split(/[\s\/\\]/).reject(&:empty?)
        else
            xpath
        end
    end
end
