Orchestrator::Testing.mock_device 'Cisco::Switch::SnoopingCatalyst' do
    # Create some mock data
    start_id = "swport-192.168.0.1-gi4/1/2"
    mock = Aca::Tracking::SwitchPort.find_by_id(start_id) || Aca::Tracking::SwitchPort.new
    mock.connected('c4544438e158', 5.minutes.to_i, {
        device_ip: '192.168.1.16',
        switch_ip: '192.168.0.1',
        hostname: '',
        switch_name: 'SG-MARWFA61301',
        interface: 'gi4/1/2'
    })

    # Call on_load again to load the above data
    exec(:on_load)
    transmit 'SG-MARWFA61301>'
    wait(1500)

    # Should have configured the tracking data above
    mock = Aca::Tracking::SwitchPort.find(start_id)
    expect(mock.nil?).to eq false
    expect(status[:"Gi4/1/2"]).to eq({
        ip: "192.168.1.16", mac: "c4544438e158", connected: true,
        clash: false, reserved: false, username: nil, desk_id: nil
    })

    should_send "show interfaces status\n"
    transmit "show interfaces status\n"
    expect(status[:hostname]).to eq('SG-MARWFA61301')

    transmit <<-ISTATUS
Port      Name               Status       Vlan       Duplex  Speed Type 
Gi1/0/1                      notconnect   113          auto   auto 10/100/1000BaseTX
Gi1/0/2                      notconnect   113          auto   auto 10/100/1000BaseTX
Gi2/0/11                     notconnect   113          auto   auto 10/100/1000BaseTX
Gi2/0/12                     notconnect   113          auto   auto 10/100/1000BaseTX
Gi2/0/13                     notconnect   113          auto   auto 10/100/1000BaseTX
Gi2/0/14                     notconnect   113          auto   auto 10/100/1000BaseTX
Gi2/0/15                     notconnect   113          auto   auto 10/100/1000BaseTX
Gi2/0/16                     notconnect   113          auto   auto 10/100/1000BaseTX
Gi2/0/17                     notconnect   113          auto   auto 10/100/1000BaseTX
Gi2/0/18                     notconnect   113          auto   auto 10/100/1000BaseTX
 --More-- 
ISTATUS

    should_send ' '
    transmit <<-ISTATUS
Gi4/0/48                     notconnect   113          auto   auto 10/100/1000BaseTX
Gi4/1/1                      notconnect   1            auto   auto unknown
Gi4/1/2                      notconnect   1            auto   auto unknown
Te4/1/4                      connected    trunk        full    10G SFP-10GBase-SR
Po1                          connected    trunk      a-full  a-10G
ISTATUS
    wait(3500)

    # Should have updated this to be offline
    mock = Aca::Tracking::SwitchPort.find(start_id)
    expect(mock.nil?).to eq false
    expect(status[:"gi4/1/2"]).to eq({
        ip: nil, mac: nil, connected: false,
        clash: false, reserved: false, username: nil, desk_id: nil
    })

    should_send "show ip dhcp snooping binding\n"
    transmit <<-SNOOPING
Total number of binding: 2

   MAC Address       IP Address    Lease (sec)     Type    VLAN Interface
------------------ --------------- ------------ ---------- ---- ----------
38:c9:86:17:a2:07  192.168.1.15    159883       learned    1    Te4/1/4
c4:54:44:38:e1:58  192.168.1.16    172522       learned    1    gi2
SNOOPING

    # Database writes
    wait(300)

    # Check and delete Database Values
    sp = Aca::Tracking::SwitchPort.find("swport-192.168.0.1-te4/1/4")
    details = sp.details
    expect(details.ip).to eq '192.168.1.15'
    expect(details.mac).to eq '38c98617a207'
    expect(details.connected).to be true
    expect(details.reserved).to be false
    expect(details.clash).to be false

    mock = Aca::Tracking::SwitchPort.find(start_id)
    details = mock.details
    expect(details.ip).to be nil
    expect(details.mac).to be nil
    expect(details.connected).to be false

    sp.destroy
    mock.destroy
end
