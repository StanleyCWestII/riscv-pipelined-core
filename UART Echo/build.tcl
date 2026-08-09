# Rung 1 UART transmitter: create project, build, program.
# Paste into the Vivado Tcl console. Safe to re-run; it deletes and rebuilds the project dir.

set srcdir "/home/scw/Files/Programming/DDCA/Chapter 7/pipelinedproject/UART Echo"
set projdir "$srcdir/uartproj"

file delete -force $projdir
create_project uartproj $projdir -part xc7a100tcsg324-1 -force

add_files [list "$srcdir/uartecho.sv" "$srcdir/top.sv"]
add_files -fileset constrs_1 [list "$srcdir/top.xdc"]
set_property top top [current_fileset]
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# check nothing was optimized away before touching the board
open_run impl_1
report_utilization -name util_1

# program
open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [get_hw_devices xc7a100t_0]
set_property PROGRAM.FILE "$projdir/uartproj.runs/impl_1/top.bit" [get_hw_devices xc7a100t_0]
program_hw_devices [get_hw_devices xc7a100t_0]
