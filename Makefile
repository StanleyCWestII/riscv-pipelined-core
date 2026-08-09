# Regression for the pipelined RV32I subset.
#   make        assemble all tests, build, run
#   make asm    re-assemble only (after editing tests/*.s)
#   make clean

SRCS  := tb.sv pipelined.sv
ASM   := $(wildcard tests/*.s)
HEX   := $(ASM:.s=.hex)

.PHONY: all asm clean
all: sim
	./sim

sim: $(SRCS) $(HEX)
	iverilog -g2012 -o sim $(SRCS)

asm: $(HEX)

tests/%.hex: tests/%.s asm.py
	python3 asm.py $< $@

clean:
	rm -f sim $(HEX)
