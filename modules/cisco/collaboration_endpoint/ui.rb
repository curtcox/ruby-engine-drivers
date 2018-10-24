# frozen_string_literal: true

module Cisco; end
module CollaborationEndpoint; end

class Cisco::CollaborationEndpoint::Ui
    include ::Orchestrator::Constants

    descriptive_name 'Cisco UI'
    generic_name :CiscoUI
    implements :logic
    description 'Cisco Touch 10 UI extensions'


    # ------------------------------
    # Module callbacks

    def on_load
        on_update
    end

    def on_unload
        clear_extensions
        unbind
    end

    def on_update
        codec_mod = setting(:codec) || :VidConf
        ui_layout = setting :cisco_ui_layout

        # Allow UI layouts to be stored as JSON
        if ui_layout.is_a? Hash
            logger.warn 'attempting experimental UI layout conversion'
            # FIXME: does not currently work if keys are missing from generated
            # xml (even if they are blank). Endpoints appear to ignore any
            # layouts that do not match the expected structure perfectly.
            ui_layout = (ui_layout[:Extensions] || ui_layout).to_xml \
                root:          :Extensions,
                skip_types:    true,
                skip_instruct: true
        end

        bind(codec_mod) do
            deploy_extensions 'test', ui_layout if ui_layout
        end
    end


    # ------------------------------
    # Device event callbacks

    def on_extensions_widget_action(event)
        logger.debug event
    end


    # ------------------------------
    # UI deployment

    def deploy_extensions(id, xml_def)
        codec.xcommand 'UserInterface Extensions Set', xml_def, ConfigId: id
    end

    def list_extensions
        codec.xcommand 'UserInterface Extensions List'
    end

    def clear_extensions
        codec.xcommand 'UserInterface Extensions Clear'
    end


    # ------------------------------
    # Popup messages

    def msg_alert(text, title: '', duration: 0)
        codec.xcommand 'UserInterface Message Alert Display',
                       Text: text,
                       Title: title,
                       Duration: duration
    end

    def msg_alert_clear
        codec.xcommand 'UserInterface Message Alert Clear'
    end


    protected


    # ------------------------------
    # Internals

    # Bind to a Cisco CE device module.
    #
    # @param mod [Symbol] the id of the Cisco CE device module to bind to
    def bind(mod)
        logger.debug "binding to #{mod}"

        @codec_mod = mod.to_sym

        unsubscribe @event_binder if @event_binder
        @event_binder = system.subscribe(@codec_mod, :connected) do |notify|
            connected = notify.value
            subscribe_events if connected
            yield if block_given?
        end

        @codec_mod
    end

    # Unbind from the device module.
    def unbind
        logger.debug 'unbinding'

        unsubscribe @event_binder
        @event_binder = nil

        clear_events

        @codec_mod = nil
    end

    def bound?
        @codec_mod.nil?.!
    end

    def codec
        raise 'not currently bound to a codec module' unless bound?
        system[@codec_mod]
    end

    def ui_callbacks
        public_methods(false).each_with_object([]) do |method, callbacks|
            next if ::Orchestrator::Core::PROTECTED[method]
            callbacks << method if method[0..2] == 'on_'
        end
    end

    def event_mappings
        ui_callbacks.map do |cb|
            path = "/Event/UserInterface/#{cb[3..-1].tr! '_', '/'}"
            [path, cb]
        end
    end

    def subscribe_events
        event_mappings.map do |path, cb|
            codec.on_event path, @__config__.settings.id, cb
        end
    end

    def clear_events
        event_mappings.map do |path, _|
            codec.clear_event path
        end
    end
end
