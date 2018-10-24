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
    # UI deployment

    # Push a UI definition build with the in-room control editor to the device.
    def deploy_extensions(id, xml_def)
        codec.xcommand 'UserInterface Extensions Set', xml_def, ConfigId: id
    end

    # Retrieve the extensions currently loaded.
    def list_extensions
        codec.xcommand 'UserInterface Extensions List'
    end

    # Clear any deployed UI extensions.
    def clear_extensions
        codec.xcommand 'UserInterface Extensions Clear'
    end


    # ------------------------------
    # UI element interaction

    # Set the value of a custom UI widget.
    def widget(id, value)
        widget_action = lambda do |action, **args|
            codec.xcommand "UserInterface Extensions Widget #{action}", args
        end

        case value
        when nil
            widget_action[:UnsetValue, WidgetId: id]
        when true
            widget id, :on
        when false
            widget id, :off
        else
            widget_action[:SetValue, WidgetId: id, Value: value]
        end
    end

    BUTTON_EVENT = [:pressed, :released, :clicked].freeze

    # Callback for changes to widget state.
    def on_extensions_widget_action(event)
        id, value, type = event.values_at :WidgetId, :Value, :Type

        logger.debug { "#{id} #{type}" }

        # Track values of stateful widgets as module state vars
        self[id] = value unless BUTTON_EVENT.include?(type) && value == ''
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

        thread.all(clear_events).value

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
