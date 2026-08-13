# T2: R-type ALU coverage including signed SLT
addi x1,  x0, 12
addi x2,  x0, 10
add  x3,  x1, x2            # 22   (x2 fwd from M, x1 fwd from W)
sub  x4,  x1, x2            # 2    (x2 fwd from W, x1 via regfile)
and  x5,  x1, x2            # 0b1100 & 0b1010 = 8
or   x6,  x1, x2            # 0b1100 | 0b1010 = 14
slt  x7,  x2, x1            # 10 < 12 = 1
slt  x8,  x1, x2            # 12 < 10 = 0
addi x9,  x0, -1
slt  x10, x9, x0            # -1 < 0  = 1   (signed, not unsigned)
slt  x11, x0, x9            #  0 < -1 = 0
sub  x12, x2, x1            # 10 - 12 = -2
add  x13, x9, x9            # -1 + -1 = -2
done: beq x0, x0, done
