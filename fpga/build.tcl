# UART echo + VGA through the pipelined core: create project, build, program.
# Paste into the Vivado Tcl console. Safe to re-run; it deletes and rebuilds the project dir.

set root    "/home/christopher/Files/Programming/DDCA/Chapter 7/pipelinedproject"
set fpgadir "$root/fpga"
set uartdir "$root/uart"
set vgadir  "$root/vga"
set coredir "$root/processor"
set projdir "$fpgadir/uartproj"

file delete -force $projdir
create_project uartproj $projdir -part xc7a100tcsg324-1 -force

# top.sv instantiates uartecho, receiver, pipelined, and vgapatterngenerator.
# All five must be here or the missing ones synthesize as empty black boxes.
#
# top.sv lives beside this script in fpga/. Only one file may declare
# "module top" anywhere in the file list or Vivado will pick one arbitrarily.
add_files [list "$fpgadir/top.sv" \
                "$uartdir/uartecho.sv" \
                "$uartdir/receiver.sv" \
                "$coredir/pipelined.sv" \
                "$vgadir/vgagenerator.sv"]

# pipelined.sv does $readmemh("memory.hex", InstrMem) with a relative path.
# Adding the hex to the project is what lets synthesis find it. Assemble first:
#   python3 asm.py vga/vgatest.s memory.hex   (VGA demo)
#   python3 asm.py uart/echo.s   memory.hex   (UART echo)
# Run those from the project root.
add_files [list "$root/memory.hex"]

add_files -fileset constrs_1 [list "$fpgadir/top.xdc"]
set_property top top [current_fileset]
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Check nothing was optimized away before touching the board. If the VGA
# generator's counters are missing here, BgColor is probably unconnected.
open_run impl_1
report_utilization -name util_1

# program
open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [get_hw_devices xc7a100t_0]
set_property PROGRAM.FILE "$projdir/uartproj.runs/impl_1/top.bit" [get_hw_devices xc7a100t_0]
program_hw_devices [get_hw_devices xc7a100t_0]
