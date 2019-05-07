
# Cisco sandbox server

Basic auth

* http://cmxlocationsandbox.cisco.com/
* Username: learning
* Password: learning


## Example Request

params supported, they are exclusive

* ipAddress= (windows server, username - IP mapping)
* username=  (assumes user has logged onto the wifi)
* macAddress=(based on historical device ownership)

response data

* status code: 204 No Content when there are no results
* confidenceFactor is the radius of the 95% confidence area from the coordinates


```
GET /api/location/v2/clients
[
    {
        "macAddress": "00:00:2a:01:00:46",
        "mapInfo": {
            "mapHierarchyString": "CiscoCampus>Building 9>IDEAS!",
            "floorRefId": "723413320329068650",
            "floorDimension": {
                "length": 74.1,
                "width": 39,
                "height": 15,
                "offsetX": 0,
                "offsetY": 0,
                "unit": "FEET"
            },
            "image": {
                "imageName": "domain_0_1462212406005.PNG",
                "zoomLevel": 4,
                "width": 568,
                "height": 1080,
                "size": 1080,
                "maxResolution": 8,
                "colorDepth": 8
            },
            "tagList": [
                "Restroom",
                "Parking",
                "Travel",
                "Laydown  2",
                "Entrance",
                "Entry2",
                "charls"
            ]
        },
        "mapCoordinate": {
            "x": 19.5,
            "y": 74.1,
            "z": 0,
            "unit": "FEET"
        },
        "currentlyTracked": true,
        "confidenceFactor": 160,
        "statistics": {
            "currentServerTime": "2017-11-06T11:02:17.996+0000",
            "firstLocatedTime": "2017-10-20T15:32:17.257+0100",
            "lastLocatedTime": "2017-11-06T11:02:15.256+0000",
            "maxDetectedRssi": {
                "apMacAddress": "00:2b:01:00:0a:00",
                "band": "IEEE_802_11_B",
                "slot": 0,
                "rssi": -63,
                "antennaIndex": 0,
                "lastHeardInSeconds": 3
            }
        },
        "historyLogReason": null,
        "geoCoordinate": null,
        "rawLocation": {
            "rawX": -999,
            "rawY": -999,
            "unit": "FEET"
        },
        "networkStatus": "ACTIVE",
        "changedOn": 1509966135256,
        "ipAddress": [
            "10.10.20.229"
        ],
        "userName": "",
        "ssId": "test",
        "sourceTimestamp": null,
        "band": "IEEE_802_11_B",
        "apMacAddress": "00:2b:01:00:0a:00",
        "dot11Status": "ASSOCIATED",
        "manufacturer": "Trw",
        "areaGlobalIdList": [
            43,
            3,
            2,
            1,
            44,
            45,
            59,
            103,
            125,
            128,
            58,
            143,
            144,
            42
        ],
        "detectingControllers": "10.10.20.90",
        "bytesSent": 154,
        "bytesReceived": 140,
        "guestUser": false
    }, ...
]
```

## Example V3 API Request

```
GET /api/location/v3/clients?username=xyz
[
    {
        "notificationType": "locationupdate",
        "subscriptionName": "CMX_Api_Server_Notification_1",
        "eventId": 572966,
        "locationMapHierarchy": "CiscoCampus>Building 9>Level 4",
        "locationCoordinate": {
            "x": 84.5761,
            "y": 84.75132,
            "z": 0,
            "unit": "FEET"
        },
        "geoCoordinate": {
            "latitude": -999,
            "longitude": -999,
            "unit": "DEGREES"
        },
        "confidenceFactor": 24,
        "apMacAddress": "70:df:2f:b5:38:60",
        "associated": true,
        "username": "W52910",
        "ipAddress": [
            "172.20.0.59",
            "fe80:0000:0000:0000:f953:31c3:a5c9:1865"
        ],
        "ssid": "wsa",
        "band": "IEEE_802_11_A",
        "floorId": 788149884915780900,
        "floorRefId": "788149884915780818",
        "entity": "WIRELESS_CLIENTS",
        "deviceId": "f4:8c:50:53:bc:09",
        "lastSeen": "2018-07-06T16:04:10.486+0800",
        "rawLocation": {
            "rawX": -999,
            "rawY": -999,
            "unit": "FEET"
        },
        "tagVendorData": null,
        "locComputeType": "RSSI",
        "manufacturer": "Intel Corporate",
        "maxDetectedRssi": {
            "apMacAddress": "70:df:2f:bb:cd:40",
            "band": "IEEE_802_11_A",
            "slot": 1,
            "rssi": -53,
            "antennaIndex": 0,
            "lastHeardInSeconds": 0
        },
        "timestamp": 1530864250486,
        "sourceNotification": "127.0.0.1",
        "sourceNotificationKey": "127.0.0.1,2",
        "notificationTime": "1530864250491"
    }
]
```
