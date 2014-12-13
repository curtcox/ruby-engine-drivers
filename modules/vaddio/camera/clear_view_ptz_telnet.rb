module Vaddio; end
module Vaddio::Camera; end


# TCP Port: 23
class Vaddio::Camera::ClearViewPtzTelnet
    include ::Orchestrator::Constants    # these provide optional helper methods
    include ::Orchestrator::Transcoder   # (not used in this module)


    def on_load
        # Setup tokenisation of connection
        config({
            tokenize: true,
            indicator: "\e[J\r\n",
            delimiter: "\r\n> \e[J", # VT100 string -ESC[J
            wait_ready: "login: "
        })

        # Default send options
        defaults({
            delay: 150  # time in ms between commands giving the unit time to process
        })


        # Constants that are made available to interfaces
        self[:pan_speed_max] = 24
        self[:pan_speed_min] = 1
        self[:tilt_speed_max] = 24
        self[:tilt_speed_min] = 1
        self[:zoom_speed_max] = 7
        self[:zoom_speed_min] = 1

        # Restart schedule (prevents it crashing)
        # Every night at 01:00am restart the camera unless defined otherwise
        schedule.cron(setting(:restart_time) || '0 1 * * *') do
            reboot
        end
    end
    
    def on_unload
    end
    
    def on_update
    end
    
    def connected
        self[:power] = true
        @polling_timer = schedule.every('60s') do
            logger.debug "-- Polling Vaddio Camera"
            version    # Low priority sent to maintain the connection
        end

        # Send the login password (wait false as not expecting a response)
        send "admin\r", wait: false
        password = setting(:password) ? "#{setting(:password)}\r" : "password\r"
        send password, wait: false
    end
    
    def disconnected
        self[:power] = false

        # Disconnected will be called before connect if initial connect fails
        @polling_timer.cancel unless @polling_timer.nil?
        @polling_timer = nil
    end


    def power(state)
        # Here for compatibility with other camera modules
    end

    def power?(options = nil, &block)
        block.call unless block.nil?
    end


    # direction: left, right, stop
    def pan(direction, speed = 18)
        params = direction.to_sym == :stop ? direction : "#{direction} #{speed}"
        send "camera pan #{params}\r", name: :pan
    end

    # direction: up, down, stop
    def tilt(direction, speed = 18)
        params = direction.to_sym == :stop ? direction : "#{direction} #{speed}"
        send "camera tilt #{params}\r", name: :tilt
    end

    def home
        send "camera home\r", name: :home
    end

    # number 1->6 inclusive
    def preset(number, command = :recall)
        send "camera #{command} #{number}\r", name: :preset
    end

    # direction: in, out, stop
    def zoom(direction, speed = 4)
        params = direction.to_sym == :stop ? direction : "#{direction} #{speed}"
        send "camera zoom #{params}\r", name: :zoom
    end

    def reboot(from_now = 0)
        # Not named so it won't be stored in the queue when not connected
        # -> Named commands persist disconnect and will execute in order on connect
        send "reboot #{from_now}\r"
    end

    def version
        send "version\r", priority: 0, wait: false
    end

    
    protected


    def received(data, resolve, command)
        logger.debug "Vaddio sent #{data}"

        # Deals with multi-line responses
        data = data.split("\r\n")[-1]

        case data.to_sym
        when :OK
            :success
        when :ERROR, :"Syntax error: Unknown or incomplete command"
            warning = "Vaddio issue: #{data}"
            warning << " for command #{command[:data]}" if command
            logger.warn warning
            :abort
        else
            :ignore
        end
    end
end

