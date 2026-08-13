# T3: lw / sw, nonzero base registers, forwarded store data and base
addi x1, x0, 42
sw   x1, 16(x0)             # store data forwarded from M -> DataMem[4] = 42
addi x2, x0, 99
sw   x2, 32(x0)             # DataMem[8] = 99
lw   x3, 16(x0)             # x3 = 42
lw   x4, 32(x0)             # x4 = 99
addi x5, x0, 8
sw   x5, 0(x5)              # base AND data both forwarded -> DataMem[2] = 8
lw   x6, 0(x5)              # x6 = 8
addi x7, x0, 4
lw   x8, 12(x7)             # addr 16 -> x8 = 42  (nonzero base + offset)
sw   x8, 20(x7)             # load-use into store data -> DataMem[6] = 42
lw   x9, 24(x0)             # x9 = 42
done: beq x0, x0, done
