
window.control.systems['sys-call-center'] = {
    CallCenter: [{
        total_abandoned: 3,
        longest_wait: 125,
        longest_talk: 945,
        achievements: [
            {
                "text": "<b>Nicki is amazing</b>, she got stuff done",
                "icon": "star"
            },
            {
                "text": "<b>Nicki is amazing</b>, she got stuff done",
                "icon": "trophy"
            },
            {
                "text": "<b>Nicki is amazing</b>, she got stuff done",
                "icon": "phone"
            }
        ],
        queues: {
            "Police": {
              queue_length: 1,
              abandoned: 0,
              total_calls: 8,
              // Asssuming seconds here
              average_wait: 12,
              max_wait: 36,
              average_talk: 540,
              on_calls: 1
            },
            "Injury": {
              queue_length: 2,
              abandoned: 1,
              total_calls: 16,
              // Asssuming seconds here
              average_wait: 24,
              max_wait: 91,
              average_talk: 238,
              on_calls: 2
            },
            "Incident": {
              queue_length: 0,
              abandoned: 0,
              total_calls: 1,
              // Asssuming seconds here
              average_wait: 5,
              max_wait: 5,
              average_talk: 49,
              on_calls: 0
            },
            "Specialist Support": {
              queue_length: 0,
              abandoned: 0,
              total_calls: 1,
              // Asssuming seconds here
              average_wait: 5,
              max_wait: 5,
              average_talk: 49,
              on_calls: 0
            },
            "E-Safety": {
              queue_length: 0,
              abandoned: 0,
              total_calls: 1,
              // Asssuming seconds here
              average_wait: 5,
              max_wait: 5,
              average_talk: 49,
              on_calls: 1
            },
            "Inquires": {
              queue_length: 0,
              abandoned: 0,
              total_calls: 2,
              // Asssuming seconds here
              average_wait: 7,
              max_wait: 8,
              average_talk: 180,
              on_calls: 1
            },
            "Media": {
              queue_length: 0,
              abandoned: 0,
              total_calls: 1,
              // Asssuming seconds here
              average_wait: 5,
              max_wait: 5,
              average_talk: 49,
              on_calls: 0
            }
        }
    }]
};
