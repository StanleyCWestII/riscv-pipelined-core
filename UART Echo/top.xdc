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
