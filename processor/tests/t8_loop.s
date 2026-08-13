# T8: backward branch loop, and SLT cases that require the overflow defense.
# The loop doubles x1 thirty-one times to reach INT_MIN (0x80000000),
# which is the only value reachable without lui or shifts.
addi x1, x0, 1              # value
addi x2, x0, 31             # counter
addi x3, x0, -1             # decrement
loop:
add  x1, x1, x1
add  x2, x2, x3
beq  x2, x0, exit
beq  x0, x0, loop           # unconditional backward branch
exit:
slti x4, x1, 1              # INT_MIN <  1      = 1   <- overflows the subtract
slt  x5, x1, x0             # INT_MIN <  0      = 1
slt  x6, x0, x1             # 0       < INT_MIN = 0   <- overflows the subtract
slti x7, x1, -1             # INT_MIN < -1      = 1
addi x8, x0, 1
slt  x9, x8, x1             # 1       < INT_MIN = 0   <- overflows the subtract
done: beq x0, x0, done
