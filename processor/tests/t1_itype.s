# T1: I-type ALU coverage, immediate extremes, x0 semantics
addi x1,  x0, 5             # x1 = 5
addi x2,  x0, -3            # x2 = 0xFFFFFFFD  (sign extension)
addi x3,  x0, 2047          # x3 = 0x7FF       (max positive imm)
addi x4,  x0, -2048         # x4 = 0xFFFFF800  (min negative imm)
ori  x5,  x1, 8             # 5 | 8   = 13
andi x6,  x3, 240           # 0x7FF & 0xF0 = 240
slti x7,  x2, 0             # -3 < 0  = 1
slti x8,  x1, 0             #  5 < 0  = 0
slti x9,  x1, 6             #  5 < 6  = 1
addi x10, x0, 99            # x10 = 99
addi x0,  x0, 99            # write to x0 (must not be observable)
add  x11, x0, x0            # x11 = 0 proves x0 still reads as zero
done: beq x0, x0, done
