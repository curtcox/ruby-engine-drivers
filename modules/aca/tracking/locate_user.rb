# frozen_string_literal: true

module Aca; end
module Aca::Tracking; end

require 'set'
require 'aca/tracking/switch_port'
::Orchestrator::DependencyManager.load('Aca::Tracking::UserDevices', :model, :force)
::Aca::Tracking::UserDevices.ensure_design_document!

class Aca::Tracking::LocateUser
    include ::Orchestrator::Constants
    include ::Orchestrator::Security

    descriptive_name 'IP and Username to MAC lookup'
    generic_name :LocateUser
    implements :logic

    default_settings({
        meraki_enabled: false,
        meraki_scanner: 'https://url.to.scanner',
        meraki_secret: 'give me access',
        cmx_enabled: false,
        cmx_host: 'http://cmxlocationsandbox.cisco.com',
        cmx_user: 'learning',
        cmx_pass: 'learning',
        ignore_vendors: {
            # https://en.wikipedia.org/wiki/MAC_address#Address_details
            'Good Way Docking Stations' => '0050b6',
            'BizLink Docking Stations' => '9cebe8'
        },
        ignore_hostnames: {},
        accept_hostnames: {}
    })

    def on_load
        @looking_up = {}
        on_update
    end

    def on_update
        @meraki_enabled = setting(:meraki_enabled)
        if @meraki_enabled
            @scanner = UV::HttpEndpoint.new(setting(:meraki_scanner), {
                headers: {
                    Authorization: "Bearer #{setting(:meraki_secret)}"
                }
            })
        else
            @scanner = nil
        end

        @cmx_enabled = setting(:cmx_enabled)
        if @cmx_enabled
            @cmx = UV::HttpEndpoint.new(setting(:cmx_host), {
                headers: {
                    Authorization: [setting(:cmx_user), setting(:cmx_pass)]
                }
            })
        else
            @cmx = nil
        end

        @blacklist = Set.new((setting(:ignore_vendors) || {}).values)
        @ignore_hosts = Set.new((setting(:ignore_hostnames) || {}).values)
        @accept_hosts = Set.new((setting(:accept_hostnames) || {}).values)
        @warnings ||= {}
    end

    protect_method :clear_warnings, :warnings, :clean_up

    # Provides a list of users and the black listed mac addresses
    # This allows one to update configuration of these machines
    attr_reader :warnings

    def clear_warnings
        @warnings = {}
    end

    # Removes all the references to a particular vendors mac addresses
    def clean_up(vendor_mac)
        count = 0

        view = Aca::Tracking::UserDevices.by_macs
        view.stream do |devs|
            macs = devs.macs.select { |mac| mac.start_with?(vendor_mac) }
            next if macs.empty?
            macs.each do |mac|
                count += 1
                devs.remove(mac)
            end
        end

        "cleaned up #{count} references"
    end

    def lookup(*ips)
        ttl = 10.minutes.ago.to_i
        ips.each do |ip, login, domain, hostname|
            perform_lookup(ip, login, domain, hostname, ttl)
        end
    end

    # This is used to directly map MAC addresses to usernames
    # Typically from a RADIUS server like MS Network Policy Server
    def associate(*macs)
        macs.each do |mac, login|
            begin
                username = ::User.bucket.get("macuser-#{mac}", quiet: true)
                # Don't overwrite domain controller discoveries
                # This differentiates BYOD from business devices
                if username.nil? || username.start_with?('byod_')
                    parts = username.split('\')
                    # ' <== fix text editor parsing issue.
                    username = parts[-1]
                    domain = parts[0]

                    user = ::Aca::Tracking::UserDevices.for_user("byod_#{login}", domain)
                    user.add(mac)
                end
            rescue => e
                logger.print_error(e, "associating MAC #{mac} to #{login}")
            end
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
        if hostname
            # Default to true if accept hosts filter is present
            ignore_host = !@accept_hosts.empty?
            check = hostname.downcase

            @accept_hosts.each do |host|
                if check.start_with? host
                    ignore_host = false
                    break
                end
            end

            @ignore_hosts.each do |host|
                if check.start_with? host
                    ignore_host = true
                    break
                end
            end

            if ignore_host
                logger.debug { "ignoring hostname #{hostname} due to filter" }
                return
            end
            save_hostname_mapping(domain, login, hostname) if self[hostname] != login
        end

        # prevents concurrent and repeat lookups for the one IP and user
        return if self[ip] == login || @looking_up[ip]
        begin
            @looking_up[ip] = true
            logger.debug { "Looking up #{ip} for #{domain}\\#{login}" }

            mac = Aca::Tracking::SwitchPort.find_by_device_ip(ip)&.mac_address
            if mac && @blacklist.include?(mac[0..5])
                logger.warn "blacklisted device detected for #{domain}\\#{login}"
                @warnings[login] = mac
                return
            end

            if mac && self[mac] != login
                logger.debug { "MAC #{mac} found for #{ip} == #{login}" }

                user = ::Aca::Tracking::UserDevices.for_user(login, domain)
                user.add(mac)

                self[mac] = login
                self[ip] = login
            else
                if @meraki_enabled && mac.nil?
                    resp = @scanner.get(path: "/meraki/#{ip}").value
                    if resp.status == 200
                        details = JSON.parse(resp.body, symbolize_names: true)

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

                if @cmx_enabled && mac.nil?
                    resp = @cmx.get(path: '/api/location/v2/clients', query: {ipAddress: ip}).value
                    if resp.status != 204 && (200...300).include?(resp.status)
                        locations = JSON.parse(resp.body, symbolize_names: true)
                        if locations.present? && locations[0][:currentlyTracked] == true
                            mac = locations[0][:macAddress]

                            if self[mac] != login
                                logger.debug { "CMX found #{mac} for #{ip} == #{login}" }

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
