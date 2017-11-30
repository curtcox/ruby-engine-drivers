# frozen_string_literal: true

require_relative 'git'

module Cisco::Spark::Util::Meta
    module_function

    def version(instance)
        hash = Cisco::Spark::Util::Git.hash __dir__
        "#{instance.class.name}-#{hash}"
    end
end
