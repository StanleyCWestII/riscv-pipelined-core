# T7: RAW at every producer-consumer distance
addi x1, x0, 3
add  x2, x1, x1             # distance 1 -> forward from M
addi x3, x0, 3
nop
add  x4, x3, x3             # distance 2 -> forward from W
addi x5, x0, 3
nop
nop
add  x6, x5, x5             # distance 3 -> negedge regfile write
addi x7, x0, 3
nop
nop
nop
add  x8, x7, x7             # distance 4 -> plain regfile read
addi x9, x0, 1
addi x9, x9, 1              # chained distance-1 dependencies
addi x9, x9, 1
addi x9, x9, 1              # x9 = 4
add  x10, x1, x9            # one near operand, one far
done: beq x0, x0, done
