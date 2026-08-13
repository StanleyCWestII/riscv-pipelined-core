# Constraints for top.sv, UART echo through the pipelined core, Nexys A7-100T
# Pins copied from the Digilent Nexys-A7-100T master XDC.

# 100 MHz system clock
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }];

# USB-UART, data leaving the FPGA toward the PC
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { UART_RXD_OUT }];

# USB-UART, data arriving at the FPGA from the PC. Idles high.
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { UART_TXD_IN }];

# BTNC, the center pushbutton, drives the processor reset.
# Active high: reads 0 idle, 1 while pressed, which matches the posedge reset
# in pipelined.sv. Press and release to restart the core.
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { Reset }];

# ---------------------------------------------------------------------------
# VGA. Pins taken from vga.xdc, which constrained vgagenerator standalone.
# The clk/reset lines from that file are deliberately NOT repeated here: this
# build's clock and reset are CLK100MHZ and Reset above.
#
# These require the matching ports on top.sv. Vivado errors on a constraint
# for a port that does not exist, so add the ports before building.
# ---------------------------------------------------------------------------

## VGA red
set_property -dict { PACKAGE_PIN A3    IOSTANDARD LVCMOS33 } [get_ports { Red[0] }];
set_property -dict { PACKAGE_PIN B4    IOSTANDARD LVCMOS33 } [get_ports { Red[1] }];
set_property -dict { PACKAGE_PIN C5    IOSTANDARD LVCMOS33 } [get_ports { Red[2] }];
set_property -dict { PACKAGE_PIN A4    IOSTANDARD LVCMOS33 } [get_ports { Red[3] }];

## VGA green
set_property -dict { PACKAGE_PIN C6    IOSTANDARD LVCMOS33 } [get_ports { Green[0] }];
set_property -dict { PACKAGE_PIN A5    IOSTANDARD LVCMOS33 } [get_ports { Green[1] }];
set_property -dict { PACKAGE_PIN B6    IOSTANDARD LVCMOS33 } [get_ports { Green[2] }];
set_property -dict { PACKAGE_PIN A6    IOSTANDARD LVCMOS33 } [get_ports { Green[3] }];

## VGA blue
set_property -dict { PACKAGE_PIN B7    IOSTANDARD LVCMOS33 } [get_ports { Blue[0] }];
set_property -dict { PACKAGE_PIN C7    IOSTANDARD LVCMOS33 } [get_ports { Blue[1] }];
set_property -dict { PACKAGE_PIN D7    IOSTANDARD LVCMOS33 } [get_ports { Blue[2] }];
set_property -dict { PACKAGE_PIN D8    IOSTANDARD LVCMOS33 } [get_ports { Blue[3] }];

## VGA sync
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { Hsync }];
set_property -dict { PACKAGE_PIN B12   IOSTANDARD LVCMOS33 } [get_ports { Vsync }];
