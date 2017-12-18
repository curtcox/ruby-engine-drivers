# frozen_string_literal: true

module Cisco; end
module Cisco::Spark; end

module Cisco::Spark::ExternalSource
    include ::Cisco::Spark::Xapi::Mapper

    module Hooks
        def connected
            super
            register_feedback '/Event/UserInterface/Presentation/ExternalSource' do |action|
                logger.debug action
                # TODO update module status with active source so our modules
                # can subscribe
            end
        end
    end

    def self.included(base)
        base.prepend Hooks
    end

    # TODO: protect methods (via ::Orchestrator::Security) that manipulate
    # sources. Currently mapper does not support this from within a module.
    command 'UserInterface ExternalSource Add' => :add_source,
            ConnectorId: (1..7),
            Name: String,
            SourceIdentifier: String,
            Type: [:pc, :camera, :desktop, :document_camera, :mediaplayer,
                   :other, :whiteboard]

    command 'UserInterface ExternalsSource Remove' => :remove_source,
            SourceIdentifier: String

    command 'UserInterface ExternalsSource RemoveAll' => :clear_sources

    command 'UserInterface ExternalsSource Select' => :select_source,
            SourceIdentifier: String

    command 'UserInterface ExternalsSource State Set' => :source_state,
            State: [:Error, :Hidden, :NotReady, :Ready],
            SourceIdentifier: String,
            ErrorReason_: String

    command 'UserInterface ExternalSource List' => :list_sources
end
