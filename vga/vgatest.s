# VGA background colour driven by the processor.
#
# Memory map, decoded in pipelined.sv from ALUResultM[10] and ALUResultM[3:2]:
#   0x400   store   transmit the low byte of the stored word
#   0x404   load    status: bit 0 = TxBusy, bit 1 = RxReady
#   0x408   load    received byte; the load itself clears RxReady
#   0x40C   store   low 12 bits become the background colour   <-- new
#
# addi immediates are 12-bit SIGNED, so one addi tops out at 2047. 0xF00 is
# 3840 and does not fit. This subset has no lui and no slli, so the red value
# is built by doubling: add x11, x11, x11 is a left shift by one.

addi x10, x0, 1024          # x10 = MMIO base = 0x400

addi x11, x0, 0x0F0         # 240, green. fits in a single addi
sw   x11, 12(x10)           # 0x40C, background goes green

# Traps. NONE of these may move the colour register. Each one defeats a
# different missing term in the write guard, so an extra change in the bench
# log names which term was left out.
addi x12, x0, 0x41          # 'A'
sw   x12, 0(x10)            # 0x400: MMIO and a store, but [3:2] = 00
sw   x12, 0(x0)             # plain data memory, word 0
addi x13, x0, 0x40C         # ALU result IS 0x40C, bit 10 set, [3:2] = 11,
                            #   but MemWriteM = 0. Catches a guard that
                            #   forgot to check that this is a store at all.
sw   x13, 12(x0)            # a real store with [3:2] = 11, but bit 10 = 0,
                            #   so it belongs to data memory. Catches a guard
                            #   that forgot ALUResultM[10].

addi x11, x0, 0x780         # 1920
add  x11, x11, x11          # 3840 = 0xF00, red
sw   x11, 12(x10)           # 0x40C, background goes red

spin:
beq  x0, x0, spin           # hold the final colour forever
