# frozen_string_literal: true

require 'ostruct'

::Orchestrator::DependencyManager.load('Aca::Rooms::Base', :logic)

class Aca::Rooms::Collab < Aca::Rooms::Base
    descriptive_name 'ACA Collaboration Space'
    generic_name :System
    implements :logic
    description <<~DESC
        Logic and external control API for collaboration spaces.

        Collaboration spaces are rooms / systems where the design is centered
        around a VC system, with the primary purpose of collaborating with both
        people in room, as well as remote parties.
    DESC

    components :Power, :Io

    def on_update
        super
        logger.debug "Methods are: #{self.methods}"
        logger.debug ::Aca::Rooms::Base.new.methods
    end
end
