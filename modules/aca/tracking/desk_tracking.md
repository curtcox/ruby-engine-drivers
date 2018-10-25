# ACA Desk Tracking

## Drivers:

1. `cisco/switch/*` switches are queried for port usage and DHCP snooping tables
  * Snooping tables contain IP address to port mapping information
2. `aca/tracking/locate_user.rb` holds the [web hook](https://drive.google.com/open?id=14XIJbnvJBg23Qc_oc3JN5Ub0geETTSmTWr8Sd8YryLM) for ingesting IP to Username mappings
  * Described in backoffice as *IP and Username to MAC lookup*
3. `tracking/desk_management.rb` periodically scans through the switches mapping out desk usage
  * There are two parts to this, desk usage and desk mapping (assigning a person to the usage)
  * It also manages reservations, ensuring no more than one desk per person.


## Models:

Located in `lib/aca/tracking/*` these store the

* switch port details `switch_port.rb` tracking
  * switch IP, switch port and switch location (building, level, desk id)
  * currently connected device (IP, MAC, connection time, username - if known)
  * any reservation details (unplug time, length of reservation, who reserved it)
* username to device mappings `user_devices.rb` tracking
  * username and domain of the user
  * the last 10 mac addresses unique to that user

Switches generate the switch port models and `locate_user.rb` generates username to device mappings. `desk_management.rb` will update switch port models with user information and reservation details as required.


## API Usage

Typically when searching a user we are pulling user lists from an organisations email distribution lists. i.e. Microsoft Exchange or Google APIs.

This means we often only have the users email address as the starting point to locate them. The challenge is to convert that email address into a login name.

* there might be a consistent mapping of email address to usernames
* sometimes this is possible using exchange
* it might require an integration into active directory

In any case, once you have the username you can then use the database models to locate people:

```ruby

username = 'steve' # for instance
devices = ::Aca::Tracking::UserDevices.for_user(username)
devices.macs.each do |mac|
    location = ::Aca::Tracking::SwitchPort.locate(mac)
    if location
        # person found!
        # location is an instance of `SwitchPort`
        break
    end
end

```


## Wireless tracking crossover

Often the data being captured by `user_devices.rb` is useful for locating users on wireless networks. Wireless networks typically require one of the following to locate a user:

* username
* computer hostname (hardware with certificates installed)
* mac address (typically meraki)

So `user_devices.rb` can be configured to search wireless systems as well as network switches to locate devices. (remember it's being sent a username, hostname and IP address, with the aim of discovering the MAC address of the device at that IP address)

Hostnames are additionally saved against usernames at: `wifihost-#{domain.downcase}-#{username.downcase}`

```ruby

username = 'Steve'
key = "wifihost-aca-#{username.downcase}"
hostname = bucket.get(key, quiet: true)
hostname # => {
#    hostname: hostname,
#    username: username,
#    domain: domain,
#    created: time,
#    updated: time
# }

```


## Configuration

### Switches

All switch drivers have these common configuration items

* `building` the zone id of the building this switch is in (optional)
* `level` the zone id of the level this switch is in (required)
* `reserve_time` the time in seconds that a desk should be reserved for by default when a user unplugs (defaults to 0)


### Desk Management / Mappings

Desk management is primary agent involved with mapping switch ports to desk ids. Example configuration data:

```javascript

{
    "timezone": "Sydney",
    "desk_reserve_time": 0,
    "desk_hold_time": 0,
    "user_identifier": "username",
    "checkin": {
        "level_id": ["desk_id1", "desk_id2"]
    },
    "mappings": {
        "10.104.144.8": {
            "gi1/0/23": "table-G.001",
            "gi1/0/21": "table-G.002"
        },
        "switch.dns.name.lowercase.com": {
            "gi1/0/23": "table-1.001",
            "gi1/0/21": "table-1.002"
        },

        // Where a switch spans multiple levels
        "192.168.7.13": {
            "zone-bguG7XtJp4": {
                "port 5": "table-g.1.02",
                "port 6": "table-g.1.04",
                "port 4": "table-g.1.14",
                "port 3": "table-g.1.17",
                "port 16": "table-g.3.10",
                "port 21": "table-g.3.12",
                "port 18": "table-g.4.05",
                "port 17": "table-g.4.06"
            },
            "zone-bguHsjKcVB": {
                "port 24": "table-mz.5.22"
            },
            "multiple_levels": true // this indicates a multi-level switch
        }
    }
}

```

* `user_identifier` the function to call on the User model to obtain a username
* `desk_hold_time` exposed as status and should match the switches `reserve_time` - not used internally, for informing interfaces
* `desk_reserve_time` if a user wants to reserve their "on hold" desk, this is the maximum reserve time
* `manual_reserve_time` the max time a manual desk can be reserved for
* `checkin` the list of manual checkin desks for each level

The `"mappings"` are the only requirement and are typically ingested by creating an import script as there can be thousands.

1. Create a spreadsheet of all the table mappings ([see example](https://docs.google.com/spreadsheets/d/1VOEy5gyjrJ8HM3EIurGElRQ0V3shM0uw4JvZSGoQLG4/edit?usp=sharing))
2. You can publish a TSV to the web to simplify or scheduling regular imports
  * click `file -> publish to the web`
  * select the spreadsheet tab and then change the format to `.tsv` (tab-seperated values)
  * click publish and copy the url
  * This is the published URL of the [example sheet](https://docs.google.com/spreadsheets/d/e/2PACX-1vQbqkFZS-VpaN42y4kxlDUiO8BCh553l5lPU-zaaMFa69-jsUZYYGn8v81atyLpMMvhD_atiP4GFf-W/pub?gid=0&single=true&output=tsv) above


Import script for the spreadsheet above:
Usage:

* `rake import:desk_details` to download from the web
* `rake import:desk_details['/file/path.tsv']`

```ruby

require 'net/http'
require 'set'

namespace :import do
    desc 'Imports desk to switch mapping details'
    task(:desk_details, [:file_name] => [:environment])  do |task, args|

        # simplest to hard code the system id
        systemId = 'sys-ZHYP~cStxZ'
        file_name = args[:file_name]

        tsv = if file_name.present?
            File.read(file_name)
        else
            # Published spreadsheet
            location = "https://docs.google.com/spreadsheets/d/e/2PACX-1vQbqkFZS-VpaN42y4kxlDUiO8BCh553l5lPU-zaaMFa69-jsUZYYGn8v81atyLpMMvhD_atiP4GFf-W/pub?gid=0&amp;single=true&amp;output=tsv"

            uri = URI(location)
            request = Net::HTTP::Get.new(uri)
            http = Net::HTTP.new(uri.hostname, uri.port)
            # http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            http.use_ssl = true
            response = http.request(request)
            raise "error requesting mappings #{response.code}\n#{response.body}" unless response.code == '200'
            response.body
        end

        count = 0
        desk_saved = Set.new
        mappings = {}
        switch_ports = {}

        # ignore empty rows
        rows = tsv.split("\n").reject { |r| r.strip.empty? }
        puts "importing #{rows.length - 1} desks"

        rows.each_with_index do |row, index|
            # ignore header
            next if index == 0
            columns = row.split("\t")

            # Grab the data
            level_num = columns[2].strip
            port_id = columns[3].strip.downcase
            switch_ip = "#{columns[4].strip.downcase}.host.com"
            desk_id = columns[8].strip

            if desk_id.empty?
                puts "no desk id: #{row}"
                next
            end

            if desk_saved.include? desk_id
                puts "duplicate desk id: #{desk_id}"
                next
            end

            if level_num.empty?
                puts "no level number: #{row}"
                next
            end

            # Transform the data as required to match maps
            # desk_id = desk_id.upcase

            # Are we looking at a network switch desk or a manual check-in desk
            if port_id.empty? || switch_ip.empty?
                # no manual desks
                puts "no port id for desk: #{desk_id}"
                next
            else
                switch_check = "#{port_id} on #{switch_ip}"

                # Report issues with the data
                if switch_ports.has_key? switch_check
                    puts "#{switch_check} duplicate desk #{desk_id} - already assigned to #{switch_ports[switch_check]}"
                    next
                end

                mappings[switch_ip] ||= {}
                mappings[switch_ip][port_id] = desk_id

                switch_ports[switch_check] = desk_id
            end

            count += 1
            desk_saved << desk_id
        end

=begin
        # If desks cross floors then we need to structure mappings to indicate this.
        floors = {
            'table-m' => 'zone-bguHsjKcVB',
            'table-g' => 'zone-bguG7XtJp4'
        }

        new_mappings = {}
        mappings.each do |switch, port_map|
            floor_mapping = {}
            port_map.each do |port, desk_id|
                floor = floors[desk_id[0..6]]
                floor_mapping[floor] ||= {}
                floor_mapping[floor][port] = desk_id
            end

            if floor_mapping.size > 1
                floor_mapping['multiple_levels'] = true
                puts "note: switch #{switch} spans #{floor_mapping.size - 1} floors"
                new_mappings[switch] = floor_mapping
            else
                new_mappings[switch] = port_map
            end
        end
        mappings = new_mappings
=end

        # Save the system settings
        cs = ::Orchestrator::ControlSystem.find(systemId)
        cs.settings_will_change!
        cs.settings[:mappings] = mappings
        # cs.settings[:checkin] = checkins (manual desks)

        puts "saving #{count} desks!"

        cs.save!(with_cas: true)

        # Confirm save
        conf = ::Orchestrator::ControlSystem.find(systemId)
        raise 'save failed' unless cs.settings.inspect == conf.settings.inspect
    end
end

```


## Miscellaneous

### Reset all data

A lot of data is cached to avoid processing when it isn't required.
You can reset all of this by doing the following:

* `require 'aca/tracking/switch_port'`
* `Aca::Tracking::SwitchPort.by_switch_ip.each(&:destroy)`
* `Aca::Tracking::UserDevices.by_domain.each(&:destroy)`

this will all automatically be regenerated


### Temporary assigning docking station MAC addresses

You might want to temporarily assign MAC addresses to docking stations that require
software to propagate MAC addresses.
In case some staff members don't have the correct configuration or there is a driver
issue.

* NOTE:: we have seen cases where MAC address propagation does not work between
different driver versions, so all driver releases should be tested for capability.

MAC addresses that are assigned temporarily require multiple touch points.

1. `locate_user.rb` checks if a temporary key in the database exists. If it exists, discovery is ignored.
2. `locate_user.rb` assigns the black listed MAC address to a staff member
3. `snooping drivers` remove the MAC address from the staff device list when the staff member unplugs
4. `snooping drivers` set the temporary ignore key in the database

Both the `locate_user.rb` script and the `snooping drivers` need to know the list of temporary blacklist macs. Setting:

* `temporary_macs` - Hash of device names to the first 6 chars of the MAC address

The `snooping drivers` also need to know the polling period of the domain controller script.

* `discovery_polling_period` - in seconds - defaults to 90


### Blacklisting always on docking stations

These keep the network port high when nothing is connected. To deal with this we
have to blacklist MAC addresses at the snooping driver level. Settings:

* `ignore_macs` - Hash of device names to the first 6 chars of the MAC address

The system deals with this by only updating the list of live ports after querying
the snooping database. This way if a blacklisted device is found the status of the
port can be set to not-connected.
