# encoding: ASCII-8BIT
# frozen_string_literal: true

module Polycom; end
module Polycom::RealPresence; end

class Polycom::RealPresence::GroupSeries
    include ::Orchestrator::Constants
    include ::Orchestrator::Transcoder
    include ::Orchestrator::Security

    # Communication settings
    tokenize delimiter: "\r\n"
    delay between_sends: 200
    tcp_port 24

    # Discovery Information
    descriptive_name 'Polycom RealPresence Group Series'
    generic_name :VidConf


    def on_load
        on_update
    end

    def on_update
        # TODO:: select between gaddrbook (global but not skype)
        # addrbook (local) commands
        # globaldir (includes LDAP and Skype)
    end

    def connected
        # Login
        send "#{setting(:password)}\r", priority: 99

        register
        status
        schedule.every('50s') do
            logger.debug 'Maintaining connection..'
            maintain_connection
        end
    end

    def disconnected
        schedule.clear
    end

    protect_method :reboot, :reset, :whoami, :unregister, :register
    protect_method :maintain_connection, :powerdown, :notify, :nonotify

    def reboot
        send "reboot now\r", name: :reboot
    end

    # Requires manual power on once powered down
    def powerdown
        send "powerdown\r"
    end

    def reset
        send "resetsystem\r", name: :reset
    end

    def whoami
        send "whoami\r", name: :whoami
    end

    def unregister
        send "all unregister\r", name: :register
    end

    def register
        send "all register\r", name: :register
    end

    # Lists the notification types that are currently being
    # received, or registers to receive status notifications
    def notify(event)
        send "notify #{event}\r"
    end

    def nonotify(event)
        send "nonotify #{event}\r"
    end

    def maintain_connection
        # Queries the AMX beacon state.
        send "amxdd get\r", name: :connection_maintenance, priority: 0
    end



    def answer
        send "answer video\r", name: :answer
    end

    def hangup(call_id = nil)
        if call_id
            send "hangup video #{call_id}\r"
        else
            send "hangup all\r", name: :hangup_all
        end
    end

    # Monitor1: far|near-or-far|content-or-far|all
    # Monitor2: near|far|content|near-or-far|content-or-near|content-or-far|all
    # Monitor3: rec-all|rec-far-or-near|near|far|content
    def configpresentation(setting, monitor: 1)
        send "configpresentation monitor#{monitor} #{setting}\r"
    end

    def contentauto?
        send "contentauto get\r"
    end

    def contentauto(enabled = true)
        setting = is_affirmative?(enabled) ? 'on' : 'off'
        send "contentauto #{setting}\r"
    end

    def daylightsavings?
        send "daylightsavings get\r"
    end

    def daylightsavings(enabled = true)
        setting = is_affirmative?(enabled) ? 'yes' : 'no'
        send "daylightsavings #{setting}\r"
    end

    def defaultgateway?
        send "defaultgateway get\r"
    end

    def dial_phone(number)
        send "dial phone auto \"number\"\r", name: :dial_phone
    end

    def dial_addressbook(entry)
        send "dial addressbook \"#{entry}\"\r", name: :dial_address
    end

    def received(response, resolve, command)
        logger.debug { "Polycom sent #{response}" }

        # Ignore the echo
        parts = response.split(/\s|:\s*/)
        return :ignore if parts[0].nil?

        cmd = parts[0].downcase.to_sym

        case cmd
        when :inacall, :autoanswerp2p, :remotecontrol, :microphones,
                :visualboard, :globaldirectory, :ipnetwork, :gatekeeper,
                :sipserver, :logthreshold, :meetingpassword, :rpms
            self[cmd] = parts[1]
        when :model
            self[cmd] = parts[1..-1].join(' ')
        when :serial
            self[cmd] = parts[2] if parts[1] == 'Number'
        when :software
            self[:version] = parts[2] if parts[1] == 'Version'
        when :build
            self[cmd] = parts[2]
        when :notification
            type = parts[1].to_sym
            case type
            when :callstatus
                if parts[2] == 'outgoing'
                    if parts.include?('connecting')
                        # dialing
                    elsif parts.include?('connected')
                        # in call
                    end
                else # incoming

                end
            when :mutestatus
                if parts[2] == 'near'
                    self[:muted] = parts[-1] == 'muted'
                end
            end
        end

        :success
    end
end
