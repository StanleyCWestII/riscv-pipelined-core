# Regression for the pipelined RV32I subset.
#   make        assemble all tests, build, run the 65-check core regression
#   make vga    build and run the standalone VGA timing bench
#   make top    build and run the core-drives-VGA integration bench
#   make all3   all three, in order
#   make asm    re-assemble only (after editing tests/*.s)
#   make clean

SRCS  := tb.sv pipelined.sv
ASM   := $(wildcard tests/*.s)
HEX   := $(ASM:.s=.hex)

# vgagenerator.sv lives in a directory with a space in the name, which make
# cannot carry through a prerequisite list. It is quoted in the recipes and the
# vga/top targets are phony, so they just rebuild every time. Compilation is
# under a second, so nothing is lost.
VGADIR := VGA Pattern Generator

.PHONY: all asm clean vga top all3
all: sim
	./sim

sim: $(SRCS) $(HEX)
	iverilog -g2012 -o sim $(SRCS)

asm: $(HEX)

tests/%.hex: tests/%.s asm.py
	python3 asm.py $< $@

# Standalone generator: VESA timing, sync polarity, blanking, bar count.
# No processor involved.
vga:
	iverilog -g2012 -o sim_vga tb_vga.sv "$(VGADIR)/vgagenerator.sv"
	./sim_vga

# Integration: the core executes vgatest.hex and drives the generator's
# background colour through the 0x40C memory-mapped register.
top: vgatest.hex
	iverilog -g2012 -o sim_top tb_top.sv pipelined.sv "$(VGADIR)/vgagenerator.sv"
	./sim_top

vgatest.hex: vgatest.s asm.py
	python3 asm.py $< $@

all3: all vga top

clean:
	rm -f sim sim_vga sim_top $(HEX) vgatest.hex
