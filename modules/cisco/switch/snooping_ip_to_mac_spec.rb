Orchestrator::Testing.mock_device 'Cisco::Switch::SnoopingIpToMac' do

    transmit "\n\n\nUser Name:"
    should_send "cisco\n"
    transmit "cisco\n"
    transmit "Password:"
    should_send "cisco\n"
    transmit "*****\n"

    transmit 'switch259f57#'
    wait(2500)

    should_send "show interfaces status\n"
    transmit "show interfaces status\n"
    expect(status[:hostname]).to eq('switch259f57')

    transmit <<-ISTATUS
                                             Flow Link          Back   Mdix
Port     Type         Duplex  Speed Neg      ctrl State       Pressure Mode
-------- ------------ ------  ----- -------- ---- ----------- -------- -------
gi1      1G-Copper    Full    1000  Enabled  Off  Up          Disabled On
gi2      1G-Copper      --      --     --     --  Down           --     --
gi3      1G-Copper    Full    1000  Enabled  Off  Up          Disabled On
gi4      1G-Copper    Full    1000  Enabled  Off  Up          Disabled On
gi5      1G-Copper      --      --     --     --  Down           --     --
gi6      1G-Copper      --      --     --     --  Down           --     --
gi7      1G-Copper      --      --     --     --  Down           --     --
gi8      1G-Copper      --      --     --     --  Down           --     --
gi9      1G-Combo-C     --      --     --     --  Down           --     --
gi10     1G-Combo-C     --      --     --     --  Down           --     --

                                          Flow    Link
Ch       Type    Duplex  Speed  Neg      control  State
-------- ------- ------  -----  -------- -------  -----------
Po1         --     --      --      --       --    Not Present
Po2         --     --      --      --       --    Not Present
Po3         --     --      --      --       --    Not Present
Po4         --     --      --      --       --    Not Present
Po5         --     --      --      --       --    Not Present
More: <space>,  Quit: q or CTRL+Z, One line: <return>
ISTATUS

    should_send ' '
    transmit <<-ISTATUS
Po6         --     --      --      --       --    Not Present
Po7         --     --      --      --       --    Not Present
Po8         --     --      --      --       --    Not Present
ISTATUS
    wait(3500)

    should_send "show ip dhcp snooping binding\n"
    transmit <<-SNOOPING
Total number of binding: 2

   MAC Address       IP Address    Lease (sec)     Type    VLAN Interface
------------------ --------------- ------------ ---------- ---- ----------
38:c9:86:17:a2:07  192.168.1.15    159883       learned    1    gi3
c4:54:44:38:e1:58  192.168.1.16    172522       learned    1    gi2
SNOOPING

end
