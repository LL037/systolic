<## PYNQ-Z2 Constraint File for Systolic Array Design
## Clock and Reset
# 125MHz Clock
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];
## Buttons (directly active-high on PYNQ-Z2)
# BTN0 - rst
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { rst }];
# BTN1 - start
set_property -dict { PACKAGE_PIN D20   IOSTANDARD LVCMOS33 } [get_ports { start }];
# BTN2 - clear_all
set_property -dict { PACKAGE_PIN L20   IOSTANDARD LVCMOS33 } [get_ports { clear_all }];
# BTN3 - (spare, if needed)
# set_property -dict { PACKAGE_PIN L19   IOSTANDARD LVCMOS33 } [get_ports { btn3 }];
## LEDs
# LED0 - valid_out[0]
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { valid_out[0] }];
# LED1 - valid_out[1]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { valid_out[1] }];
# LED2 - valid_out[2]
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { valid_out[2] }];
# LED3 - valid_out[3]
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { valid_out[3] }];
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { done }];
# RGB LED4 Green - busy
set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { busy }];
