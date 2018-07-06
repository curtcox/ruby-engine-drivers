# frozen_string_literal: true
# encoding: ASCII-8BIT

module Echo360; end

# Documentation: https://aca.im/driver_docs/Echo360/EchoSystemCaptureAPI_v301.pdf

class Echo360::DeviceCapture
    include ::Orchestrator::Constants
    include ::Orchestrator::Security

    # Discovery Information
    descriptive_name 'Echo365 Device Capture'
    generic_name :Capture
    implements :service

    # Communication settings
    keepalive true
    inactivity_timeout 15000

    def on_load
        on_update
    end

    def on_update
        # Configure authentication
        defaults({
            headers: {
                authorization: [setting(:username), setting(:password)]
            }
        })
    end

    STATUS_CMDS = {
        system_status: :system,
        capture_status: :captures,
        next: :next_capture,
        current: :current_capture,
        state: :monitoring
    }

    STATUS_CMDS.each do |function, route|
        define_method function do
            get("/status/#{route}") do |response|
                check(response) { |json| process_status json }
            end
        end
    end

    protect_method :restart_application, :reboot, :captures, :upload

    def restart_application
        post('/diagnostics/restart_all') { :success }
    end

    def reboot
        post('/diagnostics/reboot') { :success }
    end

    def captures
        get('/diagnostics/recovery/saved-content') do |response|
            check(response) { |json| self[:captures] = json['captures']['capture'] }
        end
    end

    def upload(id)
        post("/diagnostics/recovery/#{id}/upload") do |response|
            response.status == 200 ? response.body : :abort
        end
    end

    # This will auto-start a recording
    def capture(name, duration, profile = nil)
        profile ||= self[:capture_profiles][0]
        post('/capture/new_capture', body: {
            description: name,
            duration: duration.to_i,
            capture_profile_name: profile
        }) do |response|
            response.status == 200 ? Hash.from_xml(response.body)['ok']['text'] : :abort
        end
        state
    end

    def test_capture(name, duration, profile = nil)
        profile ||= self[:capture_profiles][0]
        post('/capture/confidence_monitor', body: {
            description: name,
            duration: duration.to_i,
            capture_profile_name: profile
        }) do |response|
            response.status == 200 ? Hash.from_xml(response.body)['ok']['text'] : :abort
        end
        state
    end

    def extend(duration)
        post('/capture/confidence_monitor', body: {
            duration: duration.to_i
        }) do |response|
            response.status == 200 ? Hash.from_xml(response.body)['ok']['text'] : :abort
        end
    end

    def pause
        post('/capture/pause') do |response|
            response.status == 200 ? Hash.from_xml(response.body)['ok']['text'] : :abort
        end
    end

    def start
        post('/capture/record') do |response|
            response.status == 200 ? Hash.from_xml(response.body)['ok']['text'] : :abort
        end
    end

    alias_method :resume, :start
    alias_method :record, :start

    def stop
        post('/capture/stop') do |response|
            response.status == 200 ? Hash.from_xml(response.body)['ok']['text'] : :abort
        end
    end

    protected

    # Converts the response into the appropriate format and indicates success / failure
    def check(response, defer = nil)
        if response.status == 200
            begin
                yield Hash.from_xml(response.body)
                :success
            rescue => e
                defer.reject e if defer
                :abort
            end
        else
            defer.reject :failed if defer
            :abort
        end
    end

    CHECK = %w(next current)

    # Grabs the status information and sets the keys.
    # Keys ending in 's' are typically an array of the inner element
    def process_status(data)
        data['status'].each do |key, value|
            if CHECK.include?(key) && value.length < 2 && value['schedule'] == "\n"
                self[key] = nil
            elsif key[-1] == 's' && value.is_a?(Hash)
                inner = value[key[0..-2]]
                if inner
                    self[key] = inner
                else
                    self[key] = value
                end
            else
                self[key] = value
            end
        end
    end
end
