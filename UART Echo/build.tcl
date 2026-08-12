# UART echo + VGA through the pipelined core: create project, build, program.
# Paste into the Vivado Tcl console. Safe to re-run; it deletes and rebuilds the project dir.

set srcdir  "/home/christopher/Files/Programming/DDCA/Chapter 7/pipelinedproject/UART Echo"
set coredir "/home/christopher/Files/Programming/DDCA/Chapter 7/pipelinedproject"
set vgadir  "$coredir/VGA Pattern Generator"
set projdir "$srcdir/uartproj"

file delete -force $projdir
create_project uartproj $projdir -part xc7a100tcsg324-1 -force

# top.sv instantiates uartecho, receiver, pipelined, and vgapatterngenerator.
# All five must be here or the missing ones synthesize as empty black boxes.
add_files [list "$srcdir/top.sv" \
                "$srcdir/uartecho.sv" \
                "$srcdir/receiver.sv" \
                "$coredir/pipelined.sv" \
                "$vgadir/vgagenerator.sv"]

# pipelined.sv does $readmemh("memory.hex", InstrMem) with a relative path.
# Adding the hex to the project is what lets synthesis find it. Assemble first:
#   python3 asm.py vgatest.s memory.hex     (VGA demo)
#   python3 asm.py echo.s    memory.hex     (UART echo)
add_files [list "$coredir/memory.hex"]

add_files -fileset constrs_1 [list "$srcdir/top.xdc"]
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
