# frozen_string_literal: true

module Aca; end
module Aca::Tracking; end

::Orchestrator::DependencyManager.load('Aca::Tracking::UserDevices', :model, :force)
::Aca::Tracking::UserDevices.ensure_design_document!

class Aca::Tracking::LocateUser
    include ::Orchestrator::Constants

    descriptive_name 'IP and Username to MAC lookup'
    generic_name :LocateUser
    implements :logic

    def on_load
        @looking_up = {}
    end

    def on_update
    end

    def lookup(ip, login, domain = '.')
        # prevents concurrent and repeat lookups for the one IP and user
        return if @looking_up[ip] || self[ip] == login
        @looking_up[ip] = true

        logger.debug { "Looking up #{ip} for #{domain}\\#{login}" }
        bucket = ::User.bucket
        mac = ::User.bucket.get("ipmac-#{ip}", quiet: true)
        if mac && self[mac] != login
            logger.debug { "MAC #{mac} found for #{ip} == #{login}" }

            user = ::Aca::Tracking::UserDevices.for_user(login, domain)
            user.add(mac)

            self[mac] = login
            self[ip] = login
        else
            logger.debug {
                if mac
                    "MAC #{mac} known for #{ip} : #{login}"
                else
                    "unable to locate MAC for #{ip}"
                end
            }
        end
    rescue => e
        logger.print_error(e, "looking up #{ip}")
    ensure
        @looking_up.delete(ip)
    end

    # For use with shared desktop computers that anyone can log into
    # Optimally only these machines should trigger this web hook
    def logout(ip, login, domain = '.')
        # Ensure only one operation per-IP is performed at a time
        return if @looking_up[ip]
        @looking_up[ip] = true

        # Find the mac address of the IP address logging out
        mac = ::User.bucket.get("ipmac-#{ip}", quiet: true)
        return unless mac

        # Remove the username details recorded for this MAC address
        recorded_login = self[mac]
        if mac && recorded_login
            if recorded_login != login
                logger.warn { "removing #{login} however #{recorded_login} was recorded against #{mac}" }
            else
                logger.debug { "removing #{login} from #{mac}" }
            end

            user = ::Aca::Tracking::UserDevices.for_user(login, domain)
            user.remove(mac)

            self[mac] = nil
            self[ip] = nil
        end
    ensure
        @looking_up.delete(ip)
    end
end
