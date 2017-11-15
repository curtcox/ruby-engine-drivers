module Aca; end
module Aca::Tracking; end

class Aca::Tracking::LocateUser
    include ::Orchestrator::Constants

    descriptive_name 'IP and Username to MAC lookup'
    generic_name :LocateUser
    implements :logic

    def on_load
        @looking_up = {}
    end

    def on_update
        @use_domain = setting(:use_domain)
    end

    def lookup(ip, username, domain = '.')
        login = @use_domain ? "#{domain}/#{username}" : username

        # prevents concurrent and repeat lookups for the one IP and user
        return if @looking_up[ip] || self[ip] == login
        @looking_up[ip] = true

        logger.debug { "Looking up #{ip} for #{login}" }
        bucket = ::User.bucket
        mac = ::User.bucket.get("ipmac-#{ip}", quiet: true)
        if mac && self[mac] != login
            logger.debug { "MAC #{mac} found for #{ip} == #{login}" }

            # store the mac address in the database
            expire = 1.year.from_now
            mac_key = "macuser-#{mac}"

            # Associate user with the MAC address
            old_login = bucket.get(mac_key, quiet: true)
            bucket.set(mac_key, login, expire_at: expire)

            # Remove the MAC address from any previous user
            if old_login != login
                user_key = "usermacs-#{old_login}"
                user_macs = bucket.get(user_key, quiet: true)
                if user_macs
                    user_macs.delete(mac)
                    bucket.set(user_key, user_macs, expire_at: expire)
                end
            end

            # Update the users list of MAC addresses
            user_key = "usermacs-#{login}"
            user_macs = bucket.get(user_key, quiet: true) || []
            if user_macs[0] != mac
                user_macs.delete(mac)
                user_macs.unshift(mac) # ensure last seen mac is first
                user_macs.pop if user_macs.length > 10
                bucket.set(user_key, user_macs, expire_at: expire)
            end

            self[mac] = login
            self[ip] = login
        else
            logger.debug {
                if mac
                    "MAC #{mac} known for #{ip} == #{login}"
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
    def logout(ip, username, domain = '.')
        login = @use_domain ? "#{domain}/#{username}" : username

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

            expire = 1.year.from_now

            # Remove the MAC address from any previous user
            if old_login != login
                user_key = "usermacs-#{old_login}"
                user_macs = bucket.get(user_key, quiet: true)
                if user_macs
                    user_macs.delete(mac)
                    bucket.set(user_key, user_macs, expire_at: expire)
                end
            end

            # Update the users list of MAC addresses
            user_key = "usermacs-#{login}"
            user_macs = bucket.get(user_key, quiet: true)
            if user_macs
                user_macs.delete(mac)
                bucket.set(user_key, user_macs, expire_at: expire)
            end

            # remove the user lookup
            bucket.delete("macuser-#{mac}")

            self[mac] = nil
            self[ip] = nil
        end
    ensure
        @looking_up.delete(ip)
    end
end
