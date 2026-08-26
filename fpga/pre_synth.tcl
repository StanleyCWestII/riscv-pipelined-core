# Pre-synthesis hook. Copies memory.hex into the synthesis run directory.
#
# pipelined.sv loads the instruction ROM with $readmemh("memory.hex", InstrMem).
# Vivado resolves that relative path against <proj>.runs/synth_1, not the repo
# root, so adding the file with add_files is not enough. Without this copy the
# ROM reads as empty, constant propagation removes the core outward from fetch,
# and synthesis produces a hollow bitstream that still programs and asserts DONE.
#
# Attach with:
#   set_property STEPS.SYNTH_DESIGN.TCL.PRE "$fpgadir/pre_synth.tcl" [get_runs synth_1]

set root [file dirname [file dirname [file normalize [info script]]]]
file copy -force [file join $root memory.hex] [file join [pwd] memory.hex]
