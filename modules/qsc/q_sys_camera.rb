# encoding: ASCII-8BIT
# frozen_string_literal: true

module Qsc; end

class Qsc::QSysCamera
    include ::Orchestrator::Constants

    # Discovery Information
    implements :logic
    descriptive_name 'QSC PTZ Camera Proxy'
    generic_name :Camera

    def on_load
        on_update
    end

    def on_update
        @mod_id = setting(:driver) || :Mixer
        @component = setting(:component)
    end

    def power(state)
        state = is_affirmative?(state)
        camera.mute('toggle_privacy', state, @component)
    end

    def adjust_tilt(direction)
        direction = direction.to_sym

        case direction
        when :down
            camera.mute('tilt_down', true, @component)
        when :up
            camera.mute('tilt_up', true, @component)
        else # stop
            camera.mute('toggle_privacy', false, @component)
            camera.mute('tilt_down', false, @component)
        end
    end

    def adjust_pan(direction)
        direction = direction.to_sym

        case direction
        when :right
            camera.mute('pan_right', true, @component)
        when :left
            camera.mute('pan_left', true, @component)
        else # stop
            camera.mute('pan_right', false, @component)
            camera.mute('pan_left', false, @component)
        end
    end

    def home
        camera.component_trigger(@component, 'preset_home_load')
    end

    protected

    def camera
        system[@mod_id]
    end
end
