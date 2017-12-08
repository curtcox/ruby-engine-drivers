
// Will be defined in the root zone, like buildings and levels
// "tracking_system": "sys-desk-tracking"
//
win.control.systems['sys-desk-tracking'] = {
    DeskManagement: [{
        $desk_details: (desk_id: string) => {
            return this[desk_id];
        },

        $desk_usage: (building: string, level: string) => {
            return this[`${building}:${level}`] + this[`${building}:${level}:reserved`];
        },

        // The reservation settings
        hold_time: 300,     // 5min in seconds for example
        reserve_time: 7200, // 2 hours in seconds

        // Desks in use
        "building:level1": ["desk1", "desk2", "desk4", "desk5", "desk6", "desk7"],

        // People sitting at reserved desks when they shouldn't be
        "building:level1:clashes": ["desk2", "desk7"],

        // Reserved desks that are not in use but otherwise reserved
        "building:level1:reserved": ["desk3", "desk8"],

        // Number of free desks on the level
        "building:level1:occupied_count": 6,

        // If connected==false, reserved_by==your/current user, user.reserve_time < global.reserve_time and user.reserve_time + unplug_time < time.now
        //   then prompt user to reserve or release desk.
        // If conflict=true then notify that your sitting at someone elses desk
        "user_id": {
            "ip": "10.10.10.10",      // Connected devices IP address -- null if connected == false
            "mac": "12:34:45:34:67",  // Connected devices MAC address
            "connected": true,
            "desk_id": "desk1",
            "username": "username",   // only set if connected==true and should be your username in this case
            "reserved": true,         // True if reservation valid
            "reserved_by": "username",// The user who "owns" the desk might not be you - might indicate a clash but reservation might have expired
            "conflict": false,        // Only true if the reservation is valid and the desk isn't owned by you
            "reserve_time": 300,      // should only ever be set to either hold_time or reserve_time
            "unplug_time": 1511307676 // unix epoch in seconds
        },

        // Will reserve the desk that is indicated above (batch updated - up to 1min latency)
        $reserve_desk: () => {
            // Just ignore the current version of the binding and hide the message
            // The next update of the binding should be accurate
        },
        $cancel_reservation: () => {
            // Just ignore the current version of the binding and hide the message
            // The next update of the binding should be accurate
        }
    }]
};
