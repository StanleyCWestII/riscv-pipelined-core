# T4: load-use hazard in every consumer position, including a branch
addi x1, x0, 7
sw   x1, 4(x0)              # DataMem[1] = 7
lw   x2, 4(x0)
add  x3, x2, x2             # STALL: load-use into R-type -> 14
lw   x4, 4(x0)
addi x5, x4, 1              # STALL: load-use into I-type -> 8
lw   x6, 4(x0)
nop
add  x7, x6, x6             # distance 2, must NOT stall -> 14
lw   x8, 4(x0)
beq  x8, x1, hit            # STALL then FLUSH: load-use into a taken branch
addi x30, x0, 111           # squashed
addi x31, x0, 222           # squashed
hit:
addi x10, x0, 55
done: beq x0, x0, done
