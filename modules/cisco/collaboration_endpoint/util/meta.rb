# frozen_string_literal: true

require_relative 'git'

module Cisco; end
module Cisco::CollaborationEndpoint; end
module Cisco::CollaborationEndpoint::Util; end

module Cisco::CollaborationEndpoint::Util::Meta
    module_function

    def version(instance)
        hash = Cisco::CollaborationEndpoint::Util::Git.hash __dir__
        "#{instance.class.name}-#{hash}"
    end
end
