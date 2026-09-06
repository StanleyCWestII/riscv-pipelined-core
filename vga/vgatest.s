# VGA background colour driven by the processor.
#
# Memory map, decoded in pipelined.sv from ALUResultM[16] and ALUResultM[3:2]:
#   0x10000   store   transmit the low byte of the stored word
#   0x10004   load    status: bit 0 = TxBusy, bit 1 = RxReady
#   0x10008   load    received byte; the load itself clears RxReady
#   0x1000C   store   low 12 bits become the background colour
#
# addi immediates are 12-bit SIGNED, so one addi tops out at 2047. 0xF00 is
# 3840 and does not fit. The red value is built by doubling 1920.

lui  x10, 0x10              # x10 = MMIO base = 0x00010000

addi x11, x0, 0x0F0         # 240, green. fits in a single addi
sw   x11, 12(x10)           # 0x1000C, background goes green

# Traps. NONE of these may move the colour register. Each one defeats a
# different missing term in the write guard, so an extra change in the bench
# log names which term was left out.
addi x12, x0, 0x41          # 'A'
sw   x12, 0(x10)            # 0x10000: MMIO and a store, but [3:2] = 00
sw   x12, 0(x0)             # plain data memory, word 0
lui  x13, 0x10
addi x13, x13, 12           # ALU result is 0x1000C, but this is not a store.
                            #   but MemWriteM = 0. Catches a guard that
                            #   forgot to check that this is a store at all.
sw   x13, 12(x0)            # a real store with [3:2] = 11, but bit 16 = 0,
                            #   so it belongs to data memory. Catches a guard
                            #   that forgot ALUResultM[16].

addi x11, x0, 0x780         # 1920
add  x11, x11, x11          # 3840 = 0xF00, red
sw   x11, 12(x10)           # 0x1000C, background goes red

spin:
beq  x0, x0, spin           # hold the final colour forever
