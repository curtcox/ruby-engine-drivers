module Aca; end

require_relative './mac_lookup.rb'

class Aca::LocateUser
    include ::Orchestrator::Constants


    descriptive_name 'IP and Username to MAC lookup'
    generic_name :LocateUser
    implements :logic


    def on_load
        @looking_up = {}
    end

    def lookup(ip, username, domain = '.')
        login = "#{domain}/#{username}"

        # prevents concurrent and repeat lookups for the one IP and user
        return if @looking_up[ip] || self[ip] == login
        @looking_up[ip] = true

        logger.debug { "Looking up #{ip} for #{login}" }
        bucket = ::Aca::MacLookup.bucket
        mac = ::Aca::MacLookup.bucket.get("ipmac-#{ip}", quiet: true)
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
            if not user_macs.include?(mac)
                user_macs.unshift(mac)
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
end
