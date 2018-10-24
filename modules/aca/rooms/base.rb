# frozen_string_literal: true

load File.join(__dir__, 'component_manager.rb')

module Aca; end
module Aca::Rooms; end

class Aca::Rooms::Base
    include ::Orchestrator::Constants
    include ::Aca::Rooms::ComponentManager

    # ------------------------------
    # Callbacks

    def on_load
        on_update
    end

    def on_update
        self[:name] = system.name
        self[:type] = self.class.name.demodulize
    end
end
