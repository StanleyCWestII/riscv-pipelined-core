# Constraints for vgapatterngenerator on the Nexys A7-100T.
#
# Synthesize vgapatterngenerator directly as the top module. Its ports map
# straight to board pins, so no wrapper is needed for the standalone build.
#
# reset is on BTNC (center button), active high when pressed. CPU_RESETN is
# deliberately NOT used here: it is active low, so wiring it to an active-high
# reset would hold the design in reset permanently.

## 100 MHz board clock
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }]

## reset, center pushbutton, active high
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { reset }]

## VGA red
set_property -dict { PACKAGE_PIN A3  IOSTANDARD LVCMOS33 } [get_ports { Red[0] }]
set_property -dict { PACKAGE_PIN B4  IOSTANDARD LVCMOS33 } [get_ports { Red[1] }]
set_property -dict { PACKAGE_PIN C5  IOSTANDARD LVCMOS33 } [get_ports { Red[2] }]
set_property -dict { PACKAGE_PIN A4  IOSTANDARD LVCMOS33 } [get_ports { Red[3] }]

## VGA green
set_property -dict { PACKAGE_PIN C6  IOSTANDARD LVCMOS33 } [get_ports { Green[0] }]
set_property -dict { PACKAGE_PIN A5  IOSTANDARD LVCMOS33 } [get_ports { Green[1] }]
set_property -dict { PACKAGE_PIN B6  IOSTANDARD LVCMOS33 } [get_ports { Green[2] }]
set_property -dict { PACKAGE_PIN A6  IOSTANDARD LVCMOS33 } [get_ports { Green[3] }]

## VGA blue
set_property -dict { PACKAGE_PIN B7  IOSTANDARD LVCMOS33 } [get_ports { Blue[0] }]
set_property -dict { PACKAGE_PIN C7  IOSTANDARD LVCMOS33 } [get_ports { Blue[1] }]
set_property -dict { PACKAGE_PIN D7  IOSTANDARD LVCMOS33 } [get_ports { Blue[2] }]
set_property -dict { PACKAGE_PIN D8  IOSTANDARD LVCMOS33 } [get_ports { Blue[3] }]

## VGA sync
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { Hsync }]
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports { Vsync }]
