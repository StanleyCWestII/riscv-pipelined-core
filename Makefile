# Regression for the pipelined RV32I subset.
# Run every target from the project root: pipelined.sv does a relative
# $readmemh("memory.hex"), and the benches open their .hex files relative to
# the working directory too.
#
#   make        assemble all tests, build, run the 65-check core regression
#   make cache  build and run the D-cache benchmark suite
#   make vga    build and run the standalone VGA timing bench
#   make top    build and run the core-drives-VGA integration bench
#   make all3   all three, in order
#   make asm    re-assemble only (after editing processor/tests/*.s)
#   make clean

SRCS  := processor/tb.sv processor/pipelined.sv
ASM   := $(wildcard processor/tests/*.s)
HEX   := $(ASM:.s=.hex)

.PHONY: all asm clean vga top all3 cache
all: sim
	./sim

sim: $(SRCS) $(HEX)
	iverilog -g2012 -o sim $(SRCS)

asm: $(HEX)

processor/tests/%.hex: processor/tests/%.s asm.py
	python3 asm.py $< $@

# D-cache benchmarks: hit rate, miss rate, measured AMAT. No correctness
# checks here; tb.sv owns those.
BENCH_ASM := $(wildcard processor/bench/*.s)
BENCH_HEX := $(BENCH_ASM:.s=.hex)

cache: processor/tb_cache.sv processor/pipelined.sv $(BENCH_HEX)
	iverilog -g2012 -o sim_cache processor/tb_cache.sv processor/pipelined.sv
	./sim_cache

processor/bench/%.hex: processor/bench/%.s asm.py
	python3 asm.py $< $@

# Standalone generator: VESA timing, sync polarity, blanking, bar count.
# No processor involved.
vga: vga/tb_vga.sv vga/vgagenerator.sv
	iverilog -g2012 -o sim_vga $^
	./sim_vga

# Integration: the core executes vgatest.hex and drives the generator's
# background colour through the 0x40C memory-mapped register.
top: vga/vgatest.hex vga/tb_top.sv processor/pipelined.sv vga/vgagenerator.sv
	iverilog -g2012 -o sim_top vga/tb_top.sv processor/pipelined.sv vga/vgagenerator.sv
	./sim_top

vga/vgatest.hex: vga/vgatest.s asm.py
	python3 asm.py $< $@

all3: all vga top

clean:
	rm -f sim sim_vga sim_top sim_cache $(HEX) $(BENCH_HEX) vga/vgatest.hex
