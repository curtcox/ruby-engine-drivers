# frozen_string_literal: true

module Aca; end
module Aca::Tracking; end

require 'aca/tracking/switch_port'
::Orchestrator::DependencyManager.load('Aca::Tracking::UserDevices', :model, :force)
::Aca::Tracking::UserDevices.ensure_design_document!

class Aca::Tracking::LocateUser
    include ::Orchestrator::Constants

    descriptive_name 'IP and Username to MAC lookup'
    generic_name :LocateUser
    implements :logic

    default_settings({
        meraki_enabled: false,
        meraki_scanner: 'https://url.to.scanner',
        meraki_secret: 'give me access'
    })

    def on_load
        @looking_up = {}
    end

    def on_update
        @meraki_enabled = setting(:meraki_enabled)
        if @meraki_enabled
            @scanner = UV::HttpEndpoint.new(@setting(:meraki_scanner), {
                headers: {
                    Authorization: "Bearer #{setting(:meraki_secret)}"
                }
            })
        else
            @scanner = nil
        end
    end

    def lookup(*ips)
        ttl = 10.minutes.ago.to_i
        ips.each do |ip, login, domain, hostname|
            perform_lookup(ip, login, domain, hostname, ttl)
        end
    end

    # For use with shared desktop computers that anyone can log into
    # Optimally only these machines should trigger this web hook
    def logout(ip, login, domain = nil)
        # Ensure only one operation per-IP is performed at a time
        return if @looking_up[ip]
        begin
            @looking_up[ip] = true

            # Find the mac address of the IP address logging out
            mac = Aca::Tracking::SwitchPort.find_by_device_ip(ip)&.mac_address
            return unless mac

            # Remove the username details recorded for this MAC address
            recorded_login = self[mac]
            if recorded_login != login
                logger.warn { "removing #{mac} from recorded #{recorded_login} and reported #{login}" }
                user = ::Aca::Tracking::UserDevices.for_user(recorded_login)
                user.remove(mac)
            else
                logger.debug { "removing #{mac} from #{login}" }
            end

            user = ::Aca::Tracking::UserDevices.for_user(login, domain)
            user.remove(mac)

            self[mac] = nil
            self[ip] = nil
        ensure
            @looking_up.delete(ip)
        end
    end


    protected


    def perform_lookup(ip, login, domain, hostname, ttl)
        if hostname && self[hostname] != login
            save_hostname_mapping(domain, login, hostname)
        end

        # prevents concurrent and repeat lookups for the one IP and user
        return if self[ip] == login || @looking_up[ip]
        begin
            @looking_up[ip] = true
            logger.debug { "Looking up #{ip} for #{domain}\\#{login}" }

            mac = Aca::Tracking::SwitchPort.find_by_device_ip(ip)&.mac_address

            if mac && self[mac] != login
                logger.debug { "MAC #{mac} found for #{ip} == #{login}" }

                user = ::Aca::Tracking::UserDevices.for_user(login, domain)
                user.add(mac)

                self[mac] = login
                self[ip] = login
            else
                if @meraki_enabled && mac.nil?
                    resp = @scanner.get("/meraki/#{ip}").value
                    if resp.status == 200
                        details = JSON.parse(data, symbolize_names: true)

                        if details[:seenEpoch] > ttl
                            mac = details[:clientMac]

                            if self[mac] != login
                                logger.debug { "Meraki found #{mac} for #{ip} == #{login}" }

                                # NOTE:: Wireless MAC addresses stored seperately from wired MACs
                                user = ::Aca::Tracking::UserDevices.for_user("wifi_#{login}", domain)
                                user.add(mac)

                                self[mac] = login
                                self[ip] = login
                            end
                        end
                    end
                end

                logger.debug { "unable to locate MAC for #{ip}" } if mac.nil?
            end
        rescue => e
            logger.print_error(e, "looking up #{ip}")
        ensure
            @looking_up.delete(ip)
        end
    end

    def save_hostname_mapping(domain, username, hostname)
        logger.debug { "Found new machine #{hostname} for #{username}" }

        key = "wifihost-#{domain.downcase}-#{username.downcase}"
        bucket = User.bucket
        existing = bucket.get(key, quiet: true)

        if existing
            if existing[:hostname] == hostname
                logger.debug { "ignoring #{hostname} as already in database" }
                self[hostname] = username
                return
            end
            existing[:hostname] = hostname
            existing[:updated] = Time.now.to_i
            bucket.set(key, existing)
        else
            time = Time.now.to_i
            data = {
                hostname: hostname,
                username: username,
                domain: domain,
                created: time,
                updated: time
            }
            bucket.set(key, data)
        end

        self[hostname] = username
    end
end
