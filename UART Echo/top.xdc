# Constraints for top.sv, rung 1 UART transmitter, Nexys A7-100T
# Pins copied from the Digilent Nexys-A7-100T master XDC.

# 100 MHz system clock
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }];

# USB-UART, data leaving the FPGA toward the PC
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { UART_RXD_OUT }];
